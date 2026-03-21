import SwiftUI

struct StopMarkerView: View {
    let name: String
    let isHighlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isHighlighted {
                    Circle()
                        .stroke(Color.yellow.opacity(0.95), lineWidth: 3)
                        .frame(width: 30, height: 30)
                        .shadow(color: .yellow.opacity(0.45), radius: 6, x: 0, y: 0)
                }
                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                Circle()
                    .stroke(Color.white.opacity(0.95), lineWidth: 2.5)
                    .frame(width: 22, height: 22)
                Circle()
                    .stroke(Color.black.opacity(0.82), lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                Circle()
                    .fill(Color.blue.opacity(0.9))
                    .frame(width: 8, height: 8)
            }
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop \(name)")
    }

    init(name: String, isHighlighted: Bool = false, action: @escaping () -> Void) {
        self.name = name
        self.isHighlighted = isHighlighted
        self.action = action
    }
}

struct BusMarkerView: View {
    let title: String
    let heading: Double
    let fillColor: Color
    let strokeColor: Color
    let glyphColor: Color
    let labelTextColor: Color
    let labelBackgroundColor: Color
    let opacity: Double
    let scale: CGFloat
    let scaleAnimationDuration: TimeInterval
    let isHighlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(fillColor)
                        .frame(width: 34, height: 34)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.95), lineWidth: 2.4)
                        )
                        .overlay(
                            Circle()
                                .stroke(strokeColor, lineWidth: 1.4)
                        )
                    Image(systemName: "bus.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(glyphColor)
                        .rotationEffect(.degrees(heading))
                }
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(labelTextColor)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(labelBackgroundColor, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.88), lineWidth: 0.9)
                    )
            }
            .opacity(opacity)
            .scaleEffect(scale)
            .animation(.easeInOut(duration: scaleAnimationDuration), value: scale)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.yellow.opacity(isHighlighted ? 0.95 : 0), lineWidth: 2.4)
                    .padding(-4)
            )
            .shadow(
                color: isHighlighted ? .yellow.opacity(0.45) : .black.opacity(0.34),
                radius: isHighlighted ? 12 : 7,
                x: 0,
                y: isHighlighted ? 0 : 4
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
