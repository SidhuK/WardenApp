
import SwiftUI

struct InteractiveOnboardingView: View {
    @State private var currentStep = 0
    @State private var isAnimating = false
    @State private var showWelcomeMessage = false
    @State private var typewriterText = ""
    @State private var showNextButton = false
    @State private var hasStartedOnboarding = false
    @State private var completedSteps: Set<Int> = []
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    let openPreferencesView: () -> Void
    let newChat: () -> Void
    let onComplete: (() -> Void)?
    
    private let onboardingSteps = [
        OnboardingStep(
            id: 0,
            title: "Welcome to Warden 👋",
            subtitle: "Your intelligent AI companion",
            content: "Let's get you set up in just a few steps. Warden supports multiple AI providers, so you can choose the one that works best for you.",
            action: "Get Started",
            icon: "sparkles"
        ),
        OnboardingStep(
            id: 1,
            title: "Choose Your AI Provider 🤖",
            subtitle: "Connect to your favorite AI service",
            content: "Warden supports OpenAI (ChatGPT), Claude, Gemini, Ollama (local), and many more. You'll need an API key from your chosen provider.",
            action: "Set Up API",
            icon: "server.rack"
        ),
        OnboardingStep(
            id: 2,
            title: "Explore AI Personas 🎭",
            subtitle: "Customize your AI's personality",
            content: "Choose from pre-built personas like The Wordsmith, Tech Whisperer, or create your own custom AI assistant with specific instructions.",
            action: "View Personas",
            icon: "person.3.sequence"
        ),
        OnboardingStep(
            id: 3,
            title: "You're All Set! 🚀",
            subtitle: "Ready to start chatting",
            content: "You can upload images, export conversations, and switch between AI models anytime. Your conversations are stored locally and privately.",
            action: "Start Chatting",
            icon: "checkmark.circle.fill"
        )
    ]
    
    init(openPreferencesView: @escaping () -> Void, newChat: @escaping () -> Void, onComplete: (() -> Void)? = nil) {
        self.openPreferencesView = openPreferencesView
        self.newChat = newChat
        self.onComplete = onComplete
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Animated gradient background
                AnimatedGradientBackground()
                    .opacity(0.3)
                
                VStack(spacing: 0) {
                    if !hasStartedOnboarding {
                        // Welcome animation sequence
                        VStack(spacing: 24) {
                            Spacer()
                            
                            // Animated logo with particles
                            ZStack {
                                // Particle effects around logo
                                ForEach(0..<6, id: \.self) { index in
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [.blue.opacity(0.6), .purple.opacity(0.4)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 8, height: 8)
                                        .offset(
                                            x: cos(Double(index) * .pi / 3 + (isAnimating ? 2 * .pi : 0)) * 60,
                                            y: sin(Double(index) * .pi / 3 + (isAnimating ? 2 * .pi : 0)) * 60
                                        )
                                        .opacity(isAnimating ? 0.8 : 0.3)
                                        .animation(
                                            .easeInOut(duration: 3)
                                            .repeatForever(autoreverses: false),
                                            value: isAnimating
                                        )
                                }
                                
                                // Main logo
                                Image("WelcomeIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 100, height: 100)
                                    .scaleEffect(showWelcomeMessage ? 1.0 : 0.5)
                                    .opacity(showWelcomeMessage ? 1.0 : 0.0)
                                    .animation(.spring(response: 0.8, dampingFraction: 0.6), value: showWelcomeMessage)
                            }
                            
                            // Typewriter effect welcome text
                            VStack(spacing: 12) {
                                Text(typewriterText)
                                    .font(.system(size: 28, weight: .light, design: .rounded))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.center)
                                
                                if showNextButton {
                                    Button(action: startOnboarding) {
                                        HStack(spacing: 8) {
                                            Text("Let's Begin")
                                                .font(.headline)
                                            Image(systemName: "arrow.right")
                                                .font(.headline)
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 12)
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
                                    .scaleEffect(showNextButton ? 1.0 : 0.8)
                                    .opacity(showNextButton ? 1.0 : 0.0)
                                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: showNextButton)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 40)
                    } else {
                        // Step-by-step onboarding
                        VStack(spacing: 32) {
                            // Progress indicator
                            OnboardingProgressView(
                                currentStep: currentStep,
                                totalSteps: onboardingSteps.count,
                                completedSteps: completedSteps
                            )
                            .padding(.top, 20)
                            
                            Spacer()
                            
                            // Current step content
                            OnboardingStepView(
                                step: onboardingSteps[currentStep],
                                onAction: { handleStepAction() }
                            )
                            .id(currentStep) // Force re-render for animations
                            
                            // Fun tips based on current step
                            if currentStep > 0 {
                                FloatingTipView(step: currentStep)
                                    .padding(.horizontal, 40)
                            }
                            
                            Spacer()
                            
                            // Celebration overlay for final step
                            if currentStep == onboardingSteps.count - 1 {
                                CelebrationView()
                            }
                            
                            // Navigation buttons
                            HStack(spacing: 16) {
                                if currentStep > 0 {
                                    Button("Previous") {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            currentStep -= 1
                                        }
                                    }
                                    .buttonStyle(SecondaryButtonStyle())
                                }
                                
                                Spacer()
                                
                                // Skip button (except on last step)
                                if currentStep < onboardingSteps.count - 1 {
                                    Button("Skip") {
                                        skipOnboarding()
                                    }
                                    .buttonStyle(SecondaryButtonStyle())
                                    .opacity(0.7)
                                }
                                
                                if currentStep < onboardingSteps.count - 1 {
                                    Button("Next") {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            completedSteps.insert(currentStep)
                                            currentStep += 1
                                        }
                                    }
                                    .buttonStyle(PrimaryButtonStyle())
                                }
                            }
                            .padding(.horizontal, 40)
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
        }
        .onAppear {
            startWelcomeAnimation()
        }
    }
    
    private func startWelcomeAnimation() {
        isAnimating = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showWelcomeMessage = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                typewriterEffect()
            }
        }
    }
    
    private func typewriterEffect() {
        let text = "Welcome to Warden"
        typewriterText = ""
        
        for (index, character) in text.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.05) {
                typewriterText += String(character)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(text.count) * 0.05 + 0.5) {
            showNextButton = true
        }
    }
    
    private func startOnboarding() {
        withAnimation(.easeInOut(duration: 0.5)) {
            hasStartedOnboarding = true
        }
    }
    
    private func handleStepAction() {
        switch currentStep {
        case 1: // API Setup
            openPreferencesView()
        case 2: // Personas
            openPreferencesView()
        case 3: // Start Chatting
            hasCompletedOnboarding = true
            onComplete?()
            newChat()
        default:
            if currentStep < onboardingSteps.count - 1 {
                withAnimation(.easeInOut(duration: 0.3)) {
                    completedSteps.insert(currentStep)
                    currentStep += 1
                }
            }
        }
    }
    
    private func skipOnboarding() {
        hasCompletedOnboarding = true
        onComplete?()
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

struct OnboardingStepView: View {
    let step: OnboardingStep
    let onAction: () -> Void
    @State private var showContent = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: step.icon)
                .font(.system(size: 60, weight: .ultraLight))
                .foregroundColor(.accentColor)
                .scaleEffect(showContent ? 1.0 : 0.5)
                .opacity(showContent ? 1.0 : 0.0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: showContent)
            
            VStack(spacing: 12) {
                Text(step.title)
                    .font(.system(size: 32, weight: .light, design: .rounded))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text(step.subtitle)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .offset(y: showContent ? 0 : 20)
            .opacity(showContent ? 1.0 : 0.0)
            .animation(.easeOut(duration: 0.5).delay(0.2), value: showContent)
            
            Text(step.content)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 500)
                .offset(y: showContent ? 0 : 20)
                .opacity(showContent ? 1.0 : 0.0)
                .animation(.easeOut(duration: 0.5).delay(0.4), value: showContent)
            
            Button(action: onAction) {
                HStack(spacing: 8) {
                    Text(step.action)
                        .font(.headline)
                    Image(systemName: step.id == 3 ? "checkmark" : "arrow.right")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: step.id == 3 ? [.green, .mint] : [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .shadow(color: (step.id == 3 ? Color.green : Color.blue).opacity(0.3), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(showContent ? 1.0 : 0.8)
            .opacity(showContent ? 1.0 : 0.0)
            .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.6), value: showContent)
        }
        .padding(.horizontal, 40)
        .onAppear {
            showContent = true
        }
        .onDisappear {
            showContent = false
        }
    }
}

struct OnboardingProgressView: View {
    let currentStep: Int
    let totalSteps: Int
    let completedSteps: Set<Int>
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(
                        completedSteps.contains(index) ? .green :
                        index == currentStep ? .blue :
                        .gray.opacity(0.3)
                    )
                    .frame(width: 12, height: 12)
                    .scaleEffect(index == currentStep ? 1.2 : 1.0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentStep)
                
                if index < totalSteps - 1 {
                    Rectangle()
                        .fill(.gray.opacity(0.3))
                        .frame(width: 30, height: 2)
                }
            }
        }
    }
}

struct AnimatedGradientBackground: View {
    @State private var animateGradient = false
    
    var body: some View {
        LinearGradient(
            colors: [
                .blue.opacity(0.1),
                .purple.opacity(0.1),
                .pink.opacity(0.1),
                .blue.opacity(0.1)
            ],
            startPoint: animateGradient ? .topLeading : .bottomLeading,
            endPoint: animateGradient ? .bottomTrailing : .topTrailing
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animateGradient = true
            }
        }
        .ignoresSafeArea()
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
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
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.secondary)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .stroke(.secondary.opacity(0.3), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct FloatingTipView: View {
    let step: Int
    @State private var showTip = false
    @State private var tipOffset: CGFloat = 20
    
    private var tipText: String {
        switch step {
        case 1:
            return "💡 Tip: You can always change your API provider later in settings!"
        case 2:
            return "🎭 Fun fact: You can create personas for different tasks and switch between them!"
        case 3:
            return "🔒 Privacy note: All your conversations are stored locally on your device!"
        default:
            return ""
        }
    }
    
    var body: some View {
        if !tipText.isEmpty {
            HStack(spacing: 12) {
                Circle()
                    .fill(.yellow.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .scaleEffect(showTip ? 1.2 : 0.8)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: showTip)
                
                Text(tipText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.yellow.opacity(0.1))
                    .stroke(.yellow.opacity(0.3), lineWidth: 1)
            )
            .offset(y: tipOffset)
            .opacity(showTip ? 1.0 : 0.0)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showTip)
            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: tipOffset)
            .onAppear {
                showTip = true
                tipOffset = 0
            }
        }
    }
}

struct CelebrationView: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            ForEach(0..<15, id: \.self) { index in
                Circle()
                    .fill(
                        [Color.blue, Color.purple, Color.green, Color.yellow, Color.pink]
                            .randomElement() ?? .blue
                    )
                    .frame(
                        width: CGFloat.random(in: 4...8),
                        height: CGFloat.random(in: 4...8)
                    )
                    .offset(
                        x: animate ? CGFloat.random(in: -300...300) : 0,
                        y: animate ? CGFloat.random(in: -200...200) : 0
                    )
                    .opacity(animate ? 0 : 1)
                    .animation(
                        .easeOut(duration: Double.random(in: 1...2))
                        .delay(Double(index) * 0.1),
                        value: animate
                    )
            }
        }
        .onAppear {
            animate = true
        }
        .allowsHitTesting(false)
    }
}

struct InteractiveOnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        InteractiveOnboardingView(
            openPreferencesView: {},
            newChat: {},
            onComplete: nil
        )
        .frame(width: 800, height: 600)
    }
} 
