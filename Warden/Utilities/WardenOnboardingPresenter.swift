import AppKit
import Combine
import TourKit

enum WardenOnboarding {
    static let width: CGFloat = 660

    static let pages: [TourPage] = [
        TourPage(
            imageName: "tour-welcome",
            title: "AI chat on your Mac",
            description: "Warden is a native app built in SwiftUI. Your chats stay on your Mac until you send them to a provider."
        ),
        TourPage(
            imageName: "tour-providers",
            title: "Your keys, your models",
            description: "Connect OpenAI, Claude, Gemini, Perplexity, or OpenRouter. Run Ollama or LM Studio locally if you prefer."
        ),
        TourPage(
            imageName: "tour-privacy",
            title: "Projects and personas",
            description: "Group chats into projects with their own instructions. Create personas when you want a different tone or role."
        ),
        TourPage(
            imageName: "tour-features",
            title: "Files, search, and compare",
            description: "Drag in PDFs and spreadsheets. Search the web with citations. Ask up to three models the same question and pick the best answer."
        ),
        TourPage(
            imageName: "tour-ready",
            title: "Add a key to start",
            description: "Open Settings, connect your provider, and start a new chat. Use Ollama if you want everything to run locally."
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
