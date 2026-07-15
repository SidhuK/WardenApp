import SwiftUI

@MainActor
struct WelcomeScreen: View {
    var chatsCount: Int
    var apiServiceIsPresent: Bool
    let openPreferencesView: () -> Void
    let newChat: () -> Void

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var onboardingPresenter = WardenOnboardingPresenter.shared

    var body: some View {
        welcomeEmptyState
            .overlay {
                if onboardingPresenter.isPresenting {
                    onboardingBackdrop
                }
            }
        .onAppear(perform: scheduleInitialOnboardingIfNeeded)
        .onDisappear(perform: onboardingPresenter.close)
    }

    private var onboardingBackdrop: some View {
        Color.black.opacity(0.55)
            .ignoresSafeArea()
            .allowsHitTesting(true)
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

                    Text("Choose a model, then keep your chats in one Mac app.")
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
                }
                else if chatsCount == 0 {
                    VStack(spacing: 12) {
                        Text("Your provider is connected. Start a chat.")
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
                }
                else {
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
        onboardingPresenter.replay(
            onFinish: completeOnboarding,
            onDismiss: dismissOnboarding
        )
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        if apiServiceIsPresent {
            newChat()
        }
        else {
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

#Preview("Light - No API") {
    WelcomeScreen(chatsCount: 0, apiServiceIsPresent: false, openPreferencesView: {}, newChat: {})
        .preferredColorScheme(.light)
}

#Preview("Dark - With API") {
    WelcomeScreen(chatsCount: 0, apiServiceIsPresent: true, openPreferencesView: {}, newChat: {})
        .preferredColorScheme(.dark)
}
