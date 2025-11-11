import SwiftUI

struct InteractiveOnboardingView: View {
    @State private var currentStep = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    let openPreferencesView: () -> Void
    let newChat: () -> Void
    let onComplete: (() -> Void)?
    
    private let onboardingSteps = [
        OnboardingStep(
            id: 0,
            title: "Welcome to Warden",
            subtitle: "Get started with just a few steps",
            content: "Connect your AI provider and begin chatting.",
            action: "Continue",
            icon: "sparkles"
        ),
        OnboardingStep(
            id: 1,
            title: "Add an AI Provider",
            subtitle: "Connect to your favorite service",
            content: "Go to Settings to add an API key from OpenAI, Claude, Gemini, or another provider.",
            action: "Open Settings",
            icon: "server.rack"
        ),
        OnboardingStep(
            id: 2,
            title: "You're All Set",
            subtitle: "Ready to start chatting",
            content: "Your conversations are private and stored locally. You can switch between models anytime.",
            action: "Start",
            icon: "checkmark.circle.fill"
        )
    ]
    
    init(openPreferencesView: @escaping () -> Void, newChat: @escaping () -> Void, onComplete: (() -> Void)? = nil) {
        self.openPreferencesView = openPreferencesView
        self.newChat = newChat
        self.onComplete = onComplete
    }
    
    var body: some View {
        ZStack {
            AppConstants.backgroundWindow
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress indicator
                HStack(spacing: 4) {
                    ForEach(0..<onboardingSteps.count, id: \.self) { index in
                        Capsule()
                            .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.2))
                            .frame(height: 3)
                            .animation(.easeInOut(duration: 0.3), value: currentStep)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 20)
                .padding(.bottom, 40)
                
                Spacer()
                
                // Step content
                VStack(spacing: 20) {
                    // Icon
                    Image(systemName: onboardingSteps[currentStep].icon)
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(AppConstants.textSecondary)
                        .opacity(0.8)
                    
                    VStack(spacing: 8) {
                        Text(onboardingSteps[currentStep].title)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(AppConstants.textPrimary)
                        
                        Text(onboardingSteps[currentStep].subtitle)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(AppConstants.textSecondary)
                    }
                    
                    Text(onboardingSteps[currentStep].content)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(AppConstants.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 420)
                
                Spacer()
                
                // Navigation buttons
                HStack(spacing: 12) {
                    if currentStep > 0 {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentStep -= 1
                            }
                        }) {
                            Text("Back")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppConstants.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
                    Spacer()
                    
                    if currentStep < onboardingSteps.count - 1 {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentStep += 1
                            }
                        }) {
                            Text("Next")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .background(Color.accentColor)
                        .cornerRadius(6)
                    }
                    
                    if currentStep == onboardingSteps.count - 1 {
                        if currentStep == 1 {
                            Button(action: openPreferencesView) {
                                Text("Open Settings")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .background(Color.accentColor)
                            .cornerRadius(6)
                        } else if currentStep == 2 {
                            Button(action: {
                                hasCompletedOnboarding = true
                                onComplete?()
                                newChat()
                            }) {
                                Text("Start")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .background(Color.accentColor)
                            .cornerRadius(6)
                        } else {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    currentStep += 1
                                }
                            }) {
                                Text(onboardingSteps[currentStep].action)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .background(Color.accentColor)
                            .cornerRadius(6)
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }
}

struct OnboardingStep {
    let id: Int
    let title: String
    let subtitle: String
    let content: String
    let action: String
    let icon: String
}

struct InteractiveOnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        InteractiveOnboardingView(
            openPreferencesView: {},
            newChat: {},
            onComplete: nil
        )
        .frame(width: 600, height: 500)
    }
}
