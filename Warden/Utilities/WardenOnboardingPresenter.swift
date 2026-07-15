import Observation
import SwiftUI
import TourKit

enum WardenOnboarding {
    static let width: CGFloat = 660

    static let pages: [TourPage] = [
        TourPage(
            imageName: "tour-chat",
            title: "AI chat for your Mac",
            description: "Chat history stays on your Mac. Warden sends a message to a provider when you submit it."
        ),
        TourPage(
            imageName: "tour-providers",
            title: "Connect the models you use",
            description: "Add a provider in Settings, or run Ollama or LM Studio on your Mac."
        ),
        TourPage(
            imageName: "tour-project-template",
            title: "Set up a project",
            description: "Start with a template or create a project tailored to the work at hand."
        ),
        TourPage(
            imageName: "tour-projects",
            title: "Keep project chats together",
            description: "Projects keep related chats, shared instructions, and context in one place."
        ),
        TourPage(
            imageName: "tour-assistants",
            title: "Create reusable assistants",
            description: "Give assistants their own system prompts to bring the right role into each conversation."
        ),
        TourPage(
            imageName: "tour-new-assistant",
            title: "Make it your own",
            description: "Choose an icon, tune the temperature, and select a default AI service for each assistant."
        ),
    ]
}

@MainActor
@Observable
final class WardenOnboardingPresenter {
    static let shared = WardenOnboardingPresenter()

    private(set) var isPresenting = false

    private let tourController = TourKitWindowController()
    private var presentationTask: Task<Void, Never>?

    private init() {}

    func presentIfNeeded(
        apiServiceIsPresent: Bool,
        onFinish: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        guard !isPresenting else { return }

        presentationTask?.cancel()
        presentationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            }
            catch {
                return
            }

            guard !Task.isCancelled, let self, !self.isPresenting else { return }
            self.present(apiServiceIsPresent: apiServiceIsPresent, onFinish: onFinish, onDismiss: onDismiss)
        }
    }

    func present(
        apiServiceIsPresent: Bool,
        onFinish: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        guard !isPresenting else { return }

        presentationTask?.cancel()
        presentationTask = nil
        isPresenting = true

        tourController.present(
            pages: WardenOnboarding.pages,
            width: WardenOnboarding.width,
            continueButtonTitle: "Continue",
            finishButtonTitle: apiServiceIsPresent ? "Start Chat" : "Set Up Provider",
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

    func replay() {
        guard !isPresenting else { return }

        presentationTask?.cancel()
        presentationTask = nil
        isPresenting = true

        tourController.present(
            pages: WardenOnboarding.pages,
            width: WardenOnboarding.width,
            continueButtonTitle: "Continue",
            finishButtonTitle: "Done",
            onFinish: { [weak self] in
                self?.finishPresentation()
            },
            onClose: { [weak self] in
                self?.finishPresentation()
            }
        )
    }

    func close() {
        presentationTask?.cancel()
        presentationTask = nil

        guard isPresenting else { return }
        tourController.close()
        finishPresentation()
    }

    private func finishPresentation() {
        isPresenting = false
    }
}
