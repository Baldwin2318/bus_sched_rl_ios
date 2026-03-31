import SwiftUI

struct OnboardingFlowView: View {
    @ObservedObject var locationService: LocationService
    let onFinish: (_ shouldRequestLocation: Bool) -> Void

    @State private var currentPage = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.97, blue: 1.0),
                    Color(red: 0.98, green: 0.99, blue: 1.0),
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.20, green: 0.53, blue: 0.89).opacity(0.14))
                .frame(width: 260, height: 260)
                .offset(x: 130, y: -280)
                .blur(radius: 8)

            Circle()
                .fill(Color(red: 0.96, green: 0.63, blue: 0.18).opacity(0.12))
                .frame(width: 220, height: 220)
                .offset(x: -150, y: 290)
                .blur(radius: 10)

            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    if currentPage < pages.count - 1 {
                        Button("Skip") {
                            currentPage = pages.count - 1
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NearbyETATheme.secondaryText)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)

                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        pageCard(page)
                            .padding(.horizontal, 24)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.22), value: currentPage)

                pageIndicators

                actionArea
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
            }
        }
        .interactiveDismissDisabled()
    }

    private var pages: [OnboardingPage] {
        [
            OnboardingPage(
                symbol: "bus.doubledecker.fill",
                accent: Color(red: 0.20, green: 0.53, blue: 0.89),
                title: "Catch your bus faster",
                body: "Bus ETA keeps STM arrivals simple. Open the app, check what is coming, and move on without digging through too many taps."
            ),
            OnboardingPage(
                symbol: "magnifyingglass.circle.fill",
                accent: Color(red: 0.10, green: 0.64, blue: 0.49),
                title: "Nearby, search, and favorites",
                body: "See buses close to you, search routes or stops, and keep your common trips easy to reach. The app also falls back to schedules when live data is missing."
            ),
            OnboardingPage(
                symbol: "location.circle.fill",
                accent: Color(red: 0.96, green: 0.63, blue: 0.18),
                title: "Use location for the best experience",
                body: "Allow location to load stops closest to you and make the home screen feel instant. You can still keep using the app without it."
            )
        ]
    }

    private func pageCard(_ page: OnboardingPage) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 0)

            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(page.accent.opacity(0.14))
                    .frame(width: 116, height: 116)

                Image(systemName: page.symbol)
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundStyle(page.accent)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(page.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)

                Text(page.body)
                    .font(.title3)
                    .foregroundStyle(NearbyETATheme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.white.opacity(0.65), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 20, y: 10)
    }

    private var pageIndicators: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? NearbyETATheme.accentFallback : NearbyETATheme.panelBorder.opacity(0.5))
                    .frame(width: index == currentPage ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.28, dampingFraction: 0.82), value: currentPage)
            }
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        if currentPage < pages.count - 1 {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    currentPage += 1
                }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(NearbyETATheme.accentFallback)
        } else {
            VStack(spacing: 12) {
                if locationService.authorizationState == .notDetermined {
                    Button {
                        onFinish(true)
                    } label: {
                        Text("Enable Location")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NearbyETATheme.accentFallback)
                }

                Button {
                    onFinish(false)
                } label: {
                    Text(locationService.authorizationState == .notDetermined ? "Continue Without Location" : "Start Using Bus ETA")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct OnboardingPage {
    let symbol: String
    let accent: Color
    let title: String
    let body: String
}
