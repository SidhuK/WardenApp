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
                        // Subtle animated gradient background
                        AnimatedGradientBackground()
                            .opacity(0.1)

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
                                            .scaleEffect(1.0)
                                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showInteractiveOnboarding)
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
    @State private var floatOffset: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var shimmerOffset: CGFloat = -200
    @State private var glowIntensity: Double = 0.3

    var body: some View {
        ZStack {
            // Glow effect background
            Image("WelcomeIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .blur(radius: 8)
                .opacity(glowIntensity)
                .scaleEffect(1.1)
            
            // Main icon with shimmer overlay
            Image("WelcomeIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .overlay(
                    // Shimmer effect
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.3),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .rotationEffect(.degrees(45))
                        .offset(x: shimmerOffset)
                        .clipped()
                )
                .mask(
                    Image("WelcomeIcon")
                        .resizable()
                        .scaledToFit()
                )
        }
        .scaleEffect(pulseScale * (isHovered ? 1.05 : 1.0))
        .shadow(
            color: Color.accentColor.opacity(0.3),
            radius: isHovered ? 20 : 12,
            x: 0,
            y: isHovered ? 8 : 6
        )
        .offset(y: floatOffset)
        .frame(width: 120, height: 120) // Fixed frame to prevent layout changes
        .animation(.easeInOut(duration: 0.3), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                // Trigger shimmer on hover
                withAnimation(.easeInOut(duration: 0.8)) {
                    shimmerOffset = 200
                }
            }
        }
        .onAppear {
            // Floating animation - reduced range to be more subtle
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                floatOffset = -4
            }
            
            // Subtle pulse animation
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulseScale = 1.02
            }
            
            // Glow breathing effect
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                glowIntensity = 0.6
            }
            
            // Periodic shimmer
            Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
                shimmerOffset = -200
                withAnimation(.easeInOut(duration: 1.2)) {
                    shimmerOffset = 200
                }
            }
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
