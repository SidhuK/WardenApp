import AppKit
import Combine
import TourKit

enum WardenOnboarding {
    static let width: CGFloat = 660

    static let pages: [TourPage] = [
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

/// Presents TourKit's floating onboarding window exactly as shown in the TourKit demo.
@MainActor
final class WardenOnboardingPresenter: ObservableObject {
    static let shared = WardenOnboardingPresenter()

    @Published private(set) var isPresenting = false

    private let tourController = TourKitWindowController()

    private init() {}

    func presentIfNeeded(
        apiServiceIsPresent: Bool,
        onFinish: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        guard !isPresenting else { return }

        Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !isPresenting else { return }
            present(apiServiceIsPresent: apiServiceIsPresent, onFinish: onFinish, onDismiss: onDismiss)
        }
    }

    func present(
        apiServiceIsPresent: Bool,
        onFinish: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        isPresenting = true

        tourController.present(
            pages: WardenOnboarding.pages,
            width: WardenOnboarding.width,
            continueButtonTitle: "Continue",
            finishButtonTitle: "Get Started",
            onFinish: { [weak self] in
                self?.finishPresentation()
                onFinish()
            },
            onClose: { [weak self] in
                self?.finishPresentation()
                onDismiss()
            }
        )
    }

    func close() {
        guard isPresenting else { return }
        tourController.close()
        finishPresentation()
    }

    private func finishPresentation() {
        isPresenting = false
    }
}
