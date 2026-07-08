import SwiftUI

struct WelcomeScreen: View {
    var chatsCount: Int
    var apiServiceIsPresent: Bool
    let openPreferencesView: () -> Void
    let newChat: () -> Void

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @ObservedObject private var onboardingPresenter = WardenOnboardingPresenter.shared

    var body: some View {
        Group {
            if shouldShowOnboardingBackdrop {
                onboardingBackdrop
            } else {
                welcomeEmptyState
            }
        }
        .onAppear(perform: scheduleInitialOnboardingIfNeeded)
        .onDisappear {
            if onboardingPresenter.isPresenting {
                onboardingPresenter.close()
            }
        }
    }

    private var shouldShowOnboardingBackdrop: Bool {
        onboardingPresenter.isPresenting
    }

    private var onboardingBackdrop: some View {
        ZStack {
            AppConstants.backgroundWindow
                .ignoresSafeArea()
            // Dim the main window so the floating TourKit card reads like the README demo.
            Color.black.opacity(0.55)
                .ignoresSafeArea()
        }
    }

    private var welcomeEmptyState: some View {
        ZStack {
            AppConstants.backgroundWindow
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer(minLength: 40)

                WelcomeIcon()

                VStack(spacing: 8) {
                    Text("Warden")
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(AppConstants.textPrimary)

                    Text("Chat with AI models from one native Mac app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }

                if !apiServiceIsPresent {
                    VStack(spacing: 12) {
                        ModernButton(
                            "Open Settings",
                            icon: "gearshape",
                            variant: .primary,
                            size: .large,
                            action: openPreferencesView
                        )

                        ModernButton(
                            "Replay intro",
                            icon: "sparkles",
                            variant: .tertiary,
                            size: .small,
                            action: presentOnboarding
                        )
                    }
                } else if chatsCount == 0 {
                    VStack(spacing: 12) {
                        Text("You're connected. Start a chat.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        ModernButton(
                            "New Chat",
                            icon: "plus.bubble",
                            variant: .primary,
                            size: .large,
                            action: newChat
                        )
                    }
                } else {
                    VStack(spacing: 10) {
                        Text("Select a chat from the sidebar or start a new one.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        ModernButton(
                            "Replay intro",
                            icon: "questionmark.circle",
                            variant: .tertiary,
                            size: .small,
                            action: presentOnboarding
                        )
                    }
                }

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
        }
    }

    private func scheduleInitialOnboardingIfNeeded() {
        guard !hasCompletedOnboarding else { return }
        onboardingPresenter.presentIfNeeded(
            apiServiceIsPresent: apiServiceIsPresent,
            onFinish: completeOnboarding,
            onDismiss: dismissOnboarding
        )
    }

    private func presentOnboarding() {
        onboardingPresenter.present(
            apiServiceIsPresent: apiServiceIsPresent,
            onFinish: completeOnboarding,
            onDismiss: dismissOnboarding
        )
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        if apiServiceIsPresent {
            newChat()
        } else {
            openPreferencesView()
        }
    }

    private func dismissOnboarding() {
        hasCompletedOnboarding = true
    }
}

struct WelcomeIcon: View {
    var body: some View {
        Image("WelcomeIcon")
            .resizable()
            .scaledToFit()
            .frame(width: 72, height: 72)
            .foregroundStyle(.secondary)
    }
}

struct WelcomeScreen_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            WelcomeScreen(chatsCount: 0, apiServiceIsPresent: false, openPreferencesView: {}, newChat: {})
                .preferredColorScheme(.light)
                .previewDisplayName("Light - No API")

            WelcomeScreen(chatsCount: 0, apiServiceIsPresent: true, openPreferencesView: {}, newChat: {})
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark - With API")
        }
    }
}
