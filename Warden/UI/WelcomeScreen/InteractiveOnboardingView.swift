import SwiftUI

@MainActor
struct InteractiveOnboardingView: View {
    @State private var currentStep = 0
    @State private var appeared = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.colorScheme) private var colorScheme
    
    let openPreferencesView: () -> Void
    let newChat: () -> Void
    let onComplete: (() -> Void)?
    
    var body: some View {
        ZStack {
            background
            
            VStack(spacing: 0) {
                Spacer()
                stepContent
                Spacer()
                footer
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                appeared = true
            }
        }
        .onKeyPress(.leftArrow) { previousStep(); return .handled }
        .onKeyPress(.rightArrow) { nextStep(); return .handled }
        .onKeyPress(.return) { performAction(); return .handled }
        .onKeyPress(.escape) { finish(); return .handled }
    }
    
    private var background: some View {
        ZStack {
            AppConstants.backgroundWindow
            
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.accentColor.opacity(colorScheme == .dark ? 0.08 : 0.06),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 300
                    )
                )
                .frame(width: 600, height: 600)
                .offset(y: -60)
                .blur(radius: 60)
        }
        .ignoresSafeArea()
    }
    
    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch currentStep {
            case 0: welcomeStep
            case 1: providerStep
            case 2: readyStep
            default: EmptyView()
            }
        }
        .frame(maxWidth: 400)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
    }
    
    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Image("WelcomeIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
            
            VStack(spacing: 8) {
                Text("Warden")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(AppConstants.textPrimary)
                
                Text("Private AI conversations on your Mac")
                    .font(.system(size: 14))
                    .foregroundStyle(AppConstants.textSecondary)
            }
        }
    }
    
    private var providerStep: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("Connect a provider")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppConstants.textPrimary)
                
                Text("Add your API key in Settings")
                    .font(.system(size: 14))
                    .foregroundStyle(AppConstants.textSecondary)
            }
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 12)], spacing: 12) {
                ForEach(providers, id: \.name) { provider in
                    VStack(spacing: 6) {
                        Image(provider.logo)
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(AppConstants.textPrimary.opacity(0.8))
                        
                        Text(provider.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppConstants.textSecondary)
                    }
                    .frame(width: 72, height: 64)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(colorScheme == .dark
                                  ? Color.white.opacity(0.04)
                                  : Color.black.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppConstants.borderSubtle, lineWidth: 0.5)
                    )
                }
            }
            .frame(maxWidth: 320)
        }
    }
    
    private var readyStep: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 64, height: 64)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.green)
            }
            
            VStack(spacing: 8) {
                Text("You're ready")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppConstants.textPrimary)
                
                Text("Everything stays on your device")
                    .font(.system(size: 14))
                    .foregroundStyle(AppConstants.textSecondary)
            }
        }
    }
    
    private var footer: some View {
        VStack(spacing: 20) {
            stepDots
            actionBar
        }
        .padding(.bottom, 40)
        .opacity(appeared ? 1 : 0)
    }
    
    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index == currentStep
                          ? AppConstants.textPrimary
                          : AppConstants.textTertiary)
                    .frame(width: 6, height: 6)
            }
        }
    }
    
    private var actionBar: some View {
        HStack(spacing: 12) {
            if currentStep > 0 {
                Button("Back") { previousStep() }
                    .buttonStyle(OnboardingSecondaryButton())
            }
            
            Spacer()
            
            if currentStep < 2 {
                Button("Skip") { finish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppConstants.textTertiary)
                    .font(.system(size: 13))
            }
            
            Button(action: performAction) {
                Text(actionLabel)
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(OnboardingPrimaryButton())
        }
        .frame(width: 320)
    }
    
    private var actionLabel: String {
        switch currentStep {
        case 0: "Continue"
        case 1: "Open Settings"
        case 2: "Start"
        default: "Continue"
        }
    }
    
    private var providers: [(name: String, logo: String)] {
        [
            ("OpenAI", "logo_chatgpt"),
            ("Claude", "logo_claude"),
            ("Gemini", "logo_gemini"),
            ("Ollama", "logo_ollama"),
            ("Groq", "logo_groq"),
            ("Mistral", "logo_mistral")
        ]
    }
    
    private func previousStep() {
        guard currentStep > 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStep -= 1
        }
    }
    
    private func nextStep() {
        guard currentStep < 2 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStep += 1
        }
    }
    
    private func performAction() {
        switch currentStep {
        case 0:
            nextStep()
        case 1:
            openPreferencesView()
            nextStep()
        case 2:
            finish()
        default:
            break
        }
    }
    
    private func finish() {
        hasCompletedOnboarding = true
        onComplete?()
        newChat()
    }
}

private struct OnboardingPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct OnboardingSecondaryButton: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AppConstants.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colorScheme == .dark
                          ? Color.white.opacity(0.06)
                          : Color.black.opacity(0.04))
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

#Preview("Onboarding") {
    InteractiveOnboardingView(
        openPreferencesView: {},
        newChat: {},
        onComplete: nil
    )
    .frame(width: 560, height: 440)
}
