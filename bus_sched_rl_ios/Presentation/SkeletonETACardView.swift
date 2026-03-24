import SwiftUI

struct SkeletonETACardView: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(NearbyETATheme.skeletonBase)
                    .frame(width: 82, height: 52)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(NearbyETATheme.skeletonBase)
                    .frame(width: 54, height: 10)
            }

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(NearbyETATheme.skeletonBase)
                    .frame(height: 16)
                    .frame(maxWidth: 170, alignment: .leading)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(NearbyETATheme.skeletonBase)
                    .frame(height: 13)
                    .frame(maxWidth: 140, alignment: .leading)

                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(NearbyETATheme.skeletonBase)
                        .frame(width: 58, height: 11)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(NearbyETATheme.skeletonBase)
                        .frame(width: 72, height: 11)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(NearbyETATheme.skeletonBase)
                    .frame(width: 42, height: 36)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(NearbyETATheme.skeletonBase)
                    .frame(width: 28, height: 10)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(NearbyETATheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(NearbyETATheme.panelBorder, lineWidth: 1)
        )
        .shimmering()
        .accessibilityHidden(true)
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -0.9

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    NearbyETATheme.skeletonHighlight,
                                    .clear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .rotationEffect(.degrees(18))
                        .offset(x: proxy.size.width * phase)
                }
                .allowsHitTesting(false)
                .mask(content)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    phase = 0.9
                }
            }
    }
}

private extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}
