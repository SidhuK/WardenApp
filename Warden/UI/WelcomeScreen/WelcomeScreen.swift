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
                    // Original welcome screen with enhanced design
                    ZStack {
                        // Static gradient background
                        LinearGradient(
                            colors: [
                                .blue.opacity(0.05),
                                .purple.opacity(0.05),
                                .pink.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .ignoresSafeArea()

                        VStack(spacing: 32) {
                            Spacer()
                            
                            WelcomeIcon()
                            
                            VStack(spacing: 20) {
                                Text("Welcome to Warden")
                                    .font(.system(size: 32, weight: .light, design: .rounded))
                                    .foregroundColor(.primary)
                                
                                if !apiServiceIsPresent {
                                    VStack(spacing: 16) {
                                        Text("Your intelligent AI assistant")
                                            .font(.system(size: 16, weight: .regular, design: .default))
                                            .foregroundColor(.secondary)
                                        
                                        // Interactive onboarding option for new users
                                        if !hasCompletedOnboarding {
                                            Button(action: { 
                                                withAnimation(.easeInOut(duration: 0.5)) {
                                                    showInteractiveOnboarding = true
                                                }
                                            }) {
                                                HStack(spacing: 12) {
                                                    Image(systemName: "sparkles")
                                                        .font(.system(size: 16, weight: .medium))
                                                    Text("Start Interactive Setup")
                                                        .font(.system(size: 16, weight: .medium))
                                                }
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 24)
                                                .padding(.vertical, 14)
                                                .background(
                                                    Capsule()
                                                        .fill(
                                                            LinearGradient(
                                                                colors: [.blue, .purple],
                                                                startPoint: .leading,
                                                                endPoint: .trailing
                                                            )
                                                        )
                                                )
                                                .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                        
                                        Text("or")
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                        
                                        Button(action: openPreferencesView) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "gearshape")
                                                    .font(.system(size: 14, weight: .medium))
                                                Text("Open Settings")
                                                    .font(.system(size: 14, weight: .medium))
                                            }
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(.secondary.opacity(0.3), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                } else {
                                    if chatsCount == 0 {
                                        VStack(spacing: 16) {
                                            Text("Ready to start your first conversation?")
                                                .font(.system(size: 16, weight: .regular, design: .default))
                                                .foregroundColor(.secondary)
                                            
                                            Button(action: newChat) {
                                                HStack(spacing: 8) {
                                                    Image(systemName: "plus.bubble")
                                                        .font(.system(size: 14, weight: .medium))
                                                    Text("Create New Chat")
                                                        .font(.system(size: 14, weight: .medium))
                                                }
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 20)
                                                .padding(.vertical, 10)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(Color.accentColor)
                                                )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    } else {
                                        VStack(spacing: 12) {
                                            Text("Select a chat to continue, or create a new one")
                                                .font(.system(size: 16, weight: .regular, design: .default))
                                                .foregroundColor(.secondary)
                                            
                                            // Quick action to restart onboarding for existing users
                                            Button(action: { 
                                                withAnimation(.easeInOut(duration: 0.5)) {
                                                    showInteractiveOnboarding = true
                                                }
                                            }) {
                                                HStack(spacing: 8) {
                                                    Image(systemName: "arrow.clockwise")
                                                        .font(.system(size: 12))
                                                    Text("View Setup Guide")
                                                        .font(.system(size: 12))
                                                }
                                                .foregroundColor(.secondary)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(.secondary.opacity(0.2), lineWidth: 1)
                                                )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                }
                            }
                            
                            Spacer()
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
    @State private var isHovered = false

    var body: some View {
        ZStack {
            // Glow effect background
            Image("WelcomeIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .blur(radius: 8)
                .opacity(0.4)
                .scaleEffect(1.1)
            
            // Main icon
            Image("WelcomeIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
        }
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .shadow(
            color: Color.accentColor.opacity(0.3),
            radius: isHovered ? 20 : 12,
            x: 0,
            y: isHovered ? 8 : 6
        )
        .frame(width: 120, height: 120) // Fixed frame to prevent layout changes
        .animation(.easeInOut(duration: 0.3), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            // Static state - no animations
        }
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
