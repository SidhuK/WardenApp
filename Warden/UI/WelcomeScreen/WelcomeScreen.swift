import SwiftUI

struct WelcomeScreen: View {
    var chatsCount: Int
    var apiServiceIsPresent: Bool
    var customUrl: Bool
    let openPreferencesView: () -> Void
    let newChat: () -> Void
    
    @State private var showInteractiveOnboarding = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if showInteractiveOnboarding {
                    InteractiveOnboardingView(
                        openPreferencesView: openPreferencesView,
                        newChat: newChat,
                        onComplete: {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                showInteractiveOnboarding = false
                            }
                        }
                    )
                } else {
                    // Refined welcome screen
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
                                    if !hasCompletedOnboarding {
                                        Button(action: {
                                            withAnimation(.easeInOut(duration: 0.35)) {
                                                showInteractiveOnboarding = true
                                            }
                                        }) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "sparkles")
                                                    .font(.system(size: 14, weight: .medium))
                                                Text("Start interactive setup")
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
                                    }

                                    Button(action: openPreferencesView) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "gearshape")
                                                .font(.system(size: 13, weight: .medium))
                                            Text("Open Settings")
                                                .font(.system(size: 13, weight: .medium))
                                        }
                                        .foregroundStyle(AppConstants.textPrimary)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(AppConstants.borderSubtle, lineWidth: 0.9)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
                                if chatsCount == 0 {
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

                                        Button(action: {
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                showInteractiveOnboarding = true
                                            }
                                        }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "questionmark.circle")
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
                                }
                            }

                            Spacer(minLength: 40)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 40)
                    }
                }
            }
        }
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
            WelcomeScreen(chatsCount: 0, apiServiceIsPresent: false, customUrl: false, openPreferencesView: {}, newChat: {})
                .preferredColorScheme(.light)
                .previewDisplayName("Light - No API")
            
            WelcomeScreen(chatsCount: 0, apiServiceIsPresent: true, customUrl: false, openPreferencesView: {}, newChat: {})
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark - With API")
        }
    }
}
