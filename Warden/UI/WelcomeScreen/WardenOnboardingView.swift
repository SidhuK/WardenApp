import SwiftUI
import TourKit

struct WardenOnboardingView: View {
    let apiServiceIsPresent: Bool
    let onFinish: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        TourSlideshowView(
            pages: Self.pages,
            width: 660,
            continueButtonTitle: "Continue",
            finishButtonTitle: apiServiceIsPresent ? "Start Chatting" : "Open Settings",
            onFinish: onFinish,
            onClose: onDismiss
        )
        .padding()
    }

    private static let pages: [TourPage] = [
        TourPage(
            imageName: "tour-welcome",
            title: "Welcome to Warden",
            description: "A focused workspace for private AI conversations on your Mac."
        ),
        TourPage(
            imageName: "tour-providers",
            title: "Connect Any Provider",
            description: "Use OpenAI, Claude, Gemini, Ollama, Groq, and 12+ more — all from one app."
        ),
        TourPage(
            imageName: "tour-privacy",
            title: "Privacy First",
            description: "Your chats stay on your device. No telemetry, no tracking — ever."
        ),
        TourPage(
            imageName: "tour-features",
            title: "Built for Power Users",
            description: "Markdown rendering, code highlighting, attachments, MCP tools, and multi-agent workflows."
        ),
        TourPage(
            imageName: "tour-ready",
            title: "You're Ready",
            description: "Add your API key in Settings, then start your first conversation."
        ),
    ]
}

#Preview {
    WardenOnboardingView(
        apiServiceIsPresent: false,
        onFinish: {},
        onDismiss: {}
    )
    .frame(width: 800, height: 600)
}
