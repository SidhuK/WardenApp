import SwiftUI
import TourKit

@MainActor
struct WardenOnboardingView: View {
    let apiServiceIsPresent: Bool
    let openPreferencesView: () -> Void
    let newChat: () -> Void
    let onComplete: () -> Void

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        ZStack {
            AppConstants.backgroundWindow
                .ignoresSafeArea()

            TourSlideshowView(
                pages: WardenOnboardingPages.pages,
                width: 660,
                continueButtonTitle: "Continue",
                finishButtonTitle: apiServiceIsPresent ? "Start Chatting" : "Open Settings",
                onFinish: finishOnboarding,
                onClose: skipOnboarding
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func finishOnboarding() {
        hasCompletedOnboarding = true
        if apiServiceIsPresent {
            newChat()
        } else {
            openPreferencesView()
        }
        onComplete()
    }

    private func skipOnboarding() {
        hasCompletedOnboarding = true
        onComplete()
    }
}

#Preview("Onboarding") {
    WardenOnboardingView(
        apiServiceIsPresent: false,
        openPreferencesView: {},
        newChat: {},
        onComplete: {}
    )
    .frame(width: 800, height: 600)
}
