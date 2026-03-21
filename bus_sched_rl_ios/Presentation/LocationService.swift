import Foundation
import CoreLocation

enum LocationAuthorizationState: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted

    init(status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            self = .authorized
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        case .notDetermined:
            self = .notDetermined
        @unknown default:
            self = .denied
        }
    }

    var isAuthorized: Bool {
        self == .authorized
    }
}

@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published private(set) var location: CLLocationCoordinate2D?
    @Published private(set) var authorizationState: LocationAuthorizationState

    private let manager = CLLocationManager()

    override init() {
        authorizationState = LocationAuthorizationState(status: manager.authorizationStatus)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 80
    }

    func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func requestAccessAndStart() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            requestPermission()
        }
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            authorizationState = LocationAuthorizationState(status: status)
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.location = latest.coordinate
        }
    }
}
