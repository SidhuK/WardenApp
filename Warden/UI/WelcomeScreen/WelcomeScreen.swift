import SwiftUI

struct WelcomeScreen: View {
    var chatsCount: Int
    var apiServiceIsPresent: Bool
    let openPreferencesView: () -> Void
    let newChat: () -> Void

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var onboardingPresenter = WardenOnboardingPresenter()

    var body: some View {
        welcomeEmptyState
            .onAppear {
                if !hasCompletedOnboarding {
                    presentOnboarding()
                }
            }
            .onDisappear {
                onboardingPresenter.close()
            }
    }

    private var welcomeEmptyState: some View {
        ZStack {
            AppConstants.backgroundWindow
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer(minLength: 40)

                WelcomeIcon()

                VStack(spacing: 12) {
                    Text("Welcome to Warden")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(AppConstants.textPrimary)

                    Text("A focused workspace for your AI conversations.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppConstants.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }

                if !apiServiceIsPresent {
                    VStack(spacing: 14) {
                        Button(action: openPreferencesView) {
                            HStack(spacing: 8) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Open Settings")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.accentColor)
                            )
                        }
                        .buttonStyle(.plain)

                        setupGuideButton(icon: "sparkles")
                    }
                } else if chatsCount == 0 {
                    VStack(spacing: 14) {
                        Text("You are connected. Start your first conversation.")
                            .font(.system(size: 14))
                            .foregroundStyle(AppConstants.textSecondary)

                        Button(action: newChat) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.bubble")
                                    .font(.system(size: 14, weight: .medium))
                                Text("New Chat")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.accentColor)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    VStack(spacing: 10) {
                        Text("Select a chat from the sidebar or start a new one.")
                            .font(.system(size: 14))
                            .foregroundStyle(AppConstants.textSecondary)

                        setupGuideButton(icon: "questionmark.circle")
                    }
                }

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
        }
    }

    private func setupGuideButton(icon: String) -> some View {
        Button(action: presentOnboarding) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text("View setup guide")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(AppConstants.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(AppConstants.borderSubtle, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
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
            .frame(width: 80, height: 80)
            .foregroundStyle(AppConstants.textSecondary)
            .opacity(0.8)
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
