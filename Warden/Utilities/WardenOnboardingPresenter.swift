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

/// Presents TourKit's onboarding card as a child of the main window for native macOS integration.
@MainActor
final class WardenOnboardingPresenter: ObservableObject {
    static let shared = WardenOnboardingPresenter()

    @Published private(set) var isPresenting = false

    private let tourController = TourKitWindowController()
    private weak var presentedWindow: NSWindow?

    private init() {}

    func presentIfNeeded(
        apiServiceIsPresent: Bool,
        onFinish: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        guard !isPresenting else { return }

        Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !isPresenting else { return }
            present(
                apiServiceIsPresent: apiServiceIsPresent,
                onFinish: onFinish,
                onDismiss: onDismiss
            )
        }
    }

    func present(
        apiServiceIsPresent: Bool,
        onFinish: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        guard !isPresenting else {
            presentedWindow?.makeKeyAndOrderFront(nil)
            return
        }

        isPresenting = true

        let window = tourController.present(
            pages: WardenOnboarding.pages,
            width: WardenOnboarding.width,
            continueButtonTitle: "Continue",
            finishButtonTitle: apiServiceIsPresent ? "Start Chatting" : "Open Settings",
            onFinish: { [weak self] in
                self?.finishPresentation()
                onFinish()
            },
            onClose: { [weak self] in
                self?.finishPresentation()
                onDismiss()
            }
        )

        presentedWindow = window
        attachToMainWindow(window)
    }

    func close() {
        guard isPresenting else { return }

        if let window = presentedWindow, let parent = window.parent {
            parent.removeChildWindow(window)
        }

        tourController.close()
        finishPresentation()
    }

    private func finishPresentation() {
        if let window = presentedWindow, let parent = window.parent {
            parent.removeChildWindow(window)
        }
        isPresenting = false
        presentedWindow = nil
    }

    private func attachToMainWindow(_ tourWindow: NSWindow) {
        tourWindow.level = .normal

        guard let parent = NSApp.mainWindow ?? NSApp.keyWindow else {
            tourWindow.center()
            return
        }

        parent.addChildWindow(tourWindow, ordered: .above)
        center(tourWindow, in: parent)
        NSApp.activate(ignoringOtherApps: false)
        tourWindow.makeKeyAndOrderFront(nil)
    }

    private func center(_ tourWindow: NSWindow, in parent: NSWindow) {
        let parentFrame = parent.frame
        var frame = tourWindow.frame
        frame.origin.x = parentFrame.midX - frame.width / 2
        frame.origin.y = parentFrame.midY - frame.height / 2
        tourWindow.setFrame(frame, display: true)
    }
}
