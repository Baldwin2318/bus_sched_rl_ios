import SwiftUI
import MapKit
import UIKit

struct ArrivalLiveMapView: View {
    let model: ArrivalLiveMapModel

    var body: some View {
        ArrivalLiveMKMapView(model: model)
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(NearbyETATheme.panelBorder, lineWidth: 1)
            )
            .accessibilityIdentifier("arrival-live-map")
    }
}

private struct ArrivalLiveMKMapView: UIViewRepresentable {
    let model: ArrivalLiveMapModel

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.showsUserLocation = true
        mapView.isRotateEnabled = true
        mapView.pointOfInterestFilter = .excludingAll
        mapView.userTrackingMode = .none
        context.coordinator.apply(model: model, to: mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        if !mapView.showsUserLocation {
            mapView.showsUserLocation = true
        }
        if mapView.userTrackingMode != .none {
            mapView.setUserTrackingMode(.none, animated: false)
        }
        context.coordinator.apply(model: model, to: mapView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private let stopAnnotation = MKPointAnnotation()
        private let busAnnotation = MKPointAnnotation()
        private var lastOverlayHash: String?
        private var lastVisibleRectHash: String?
        private var usesRouteShapePath = false

        func apply(model: ArrivalLiveMapModel, to mapView: MKMapView) {
            stopAnnotation.title = model.stopName
            stopAnnotation.coordinate = model.stopCoordinate

            busAnnotation.title = "Bus"
            busAnnotation.coordinate = model.vehicle.coordinate
            usesRouteShapePath = model.usesRouteShapePath

            if !mapView.annotations.contains(where: { $0 === stopAnnotation }) {
                mapView.addAnnotation(stopAnnotation)
            }
            if !mapView.annotations.contains(where: { $0 === busAnnotation }) {
                mapView.addAnnotation(busAnnotation)
            }

            if let busView = mapView.view(for: busAnnotation) {
                configureBusView(
                    busView,
                    heading: model.vehicle.heading,
                    freshness: model.vehicle.freshness
                )
            }

            syncRouteOverlay(model: model, mapView: mapView)
            syncVisibleRect(model: model, mapView: mapView)
        }

        private func syncRouteOverlay(model: ArrivalLiveMapModel, mapView: MKMapView) {
            let overlayHash = "\(model.vehicle.coordinate.latitude):\(model.vehicle.coordinate.longitude):\(model.stopCoordinate.latitude):\(model.stopCoordinate.longitude):\(model.routeLine.pointCount)"
            guard overlayHash != lastOverlayHash else { return }

            mapView.removeOverlays(mapView.overlays)
            mapView.addOverlay(model.routeLine)
            lastOverlayHash = overlayHash
        }

        private func syncVisibleRect(model: ArrivalLiveMapModel, mapView: MKMapView) {
            let visibleRectHash = [
                model.vehicle.coordinate.latitude,
                model.vehicle.coordinate.longitude,
                model.stopCoordinate.latitude,
                model.stopCoordinate.longitude,
                model.userLocation?.latitude ?? 0,
                model.userLocation?.longitude ?? 0,
                Double(model.routeLine.pointCount)
            ]
                .map { String(format: "%.6f", $0) }
                .joined(separator: ":")

            guard visibleRectHash != lastVisibleRectHash else { return }

            var rect = model.routeLine.boundingMapRect
            rect = rect.union(MKMapRect(origin: MKMapPoint(model.vehicle.coordinate), size: MKMapSize(width: 0, height: 0)))
            rect = rect.union(MKMapRect(origin: MKMapPoint(model.stopCoordinate), size: MKMapSize(width: 0, height: 0)))
            if let userLocation = model.userLocation {
                rect = rect.union(MKMapRect(origin: MKMapPoint(userLocation), size: MKMapSize(width: 0, height: 0)))
            }

            if rect.isNull || rect.isEmpty {
                mapView.setRegion(model.region, animated: true)
            } else {
                mapView.setVisibleMapRect(
                    rect,
                    edgePadding: UIEdgeInsets(top: 48, left: 36, bottom: 48, right: 36),
                    animated: true
                )
            }

            lastVisibleRectHash = visibleRectHash
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor(NearbyETATheme.accentFallback).withAlphaComponent(0.8)
            renderer.lineWidth = 4
            renderer.lineDashPattern = usesRouteShapePath ? nil : [10, 8]
            renderer.lineCap = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            if annotation === busAnnotation {
                let identifier = "bus"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) ??
                    MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                configureBusView(view, heading: 0, freshness: .fresh)
                view.canShowCallout = true
                return view
            }

            if annotation === stopAnnotation {
                let identifier = "stop"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                view.markerTintColor = .systemRed
                view.glyphImage = UIImage(systemName: "mappin")
                view.canShowCallout = true
                return view
            }

            return nil
        }

        private func configureBusView(
            _ view: MKAnnotationView,
            heading: Double,
            freshness: VehicleFreshness
        ) {
            view.image = busImage
            view.centerOffset = CGPoint(x: 0, y: -16)
            view.transform = CGAffineTransform(rotationAngle: CGFloat(heading * .pi / 180))
            switch freshness {
            case .fresh:
                view.alpha = 1
            case .aging:
                view.alpha = 0.82
            case .stale:
                view.alpha = 0.58
            }
        }

        private var busImage: UIImage {
            Self.busImage
        }

        private static let busImage: UIImage = {
            let size = CGSize(width: 34, height: 34)
            return UIGraphicsImageRenderer(size: size).image { _ in
                let rect = CGRect(origin: .zero, size: size)
                UIColor(NearbyETATheme.accentFallback).setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()

                let symbolConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
                let symbol = UIImage(systemName: "bus.fill", withConfiguration: symbolConfig)?
                    .withTintColor(.white, renderingMode: .alwaysOriginal)
                let symbolSize = symbol?.size ?? .zero
                let symbolOrigin = CGPoint(
                    x: (size.width - symbolSize.width) * 0.5,
                    y: (size.height - symbolSize.height) * 0.5
                )
                symbol?.draw(at: symbolOrigin)
            }
        }()
    }
}
