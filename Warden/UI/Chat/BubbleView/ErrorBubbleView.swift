import AppKit
import SwiftUI

enum ErrorType {
    case apiError(APIError)
    case webSearchError(WebSearchError)
    case generic(Error)
}

struct ErrorMessage {
    let id = UUID()
    let type: ErrorType
    let timestamp: Date

    init(type: ErrorType, timestamp: Date) {
        self.type = type
        self.timestamp = timestamp
    }

    var presentation: ErrorPresentation { ErrorPresentation(error: self) }

    var displayTitle: String { presentation.title }

    var displayMessage: String { presentation.body }

    var canRetry: Bool { presentation.isRetryable }

    var isApiKeyError: Bool { presentation.severity == .auth }

    // MARK: - Convenience Initializers

    init(apiError: APIError, timestamp: Date = Date()) {
        self.init(type: .apiError(apiError), timestamp: timestamp)
    }

    init(webSearchError: WebSearchError, timestamp: Date = Date()) {
        self.init(type: .webSearchError(webSearchError), timestamp: timestamp)
    }

    init(tavilyError: TavilyError, timestamp: Date = Date()) {
        self.init(webSearchError: tavilyError, timestamp: timestamp)
    }

    init(error: Error, timestamp: Date = Date()) {
        if let apiError = error as? APIError {
            self.init(type: .apiError(apiError), timestamp: timestamp)
        } else if let webSearchError = error as? WebSearchError {
            self.init(type: .webSearchError(webSearchError), timestamp: timestamp)
        } else {
            self.init(type: .generic(error), timestamp: timestamp)
        }
    }
}

// MARK: - Card State

/// Countdown, automatic-retry budget and key-test status for the chat's current error card.
/// Owned by the chat view so the countdown survives the lazy list recycling the card.
@MainActor
final class ErrorCardState: ObservableObject {
    enum KeyTest: Equatable {
        case idle
        case testing
        case succeeded
        case failed(String)
    }

    @Published private(set) var secondsRemaining: Int?
    @Published private(set) var automaticAttempts = 0
    @Published var keyTest: KeyTest = .idle

    private var countdownTask: Task<Void, Never>?

    static let keyTestTimeout: TimeInterval = 30
    private var keyTestID: UUID?
    /// The handler's request task only holds it weakly, so the test's owner must be kept alive here.
    private var keyTestRunner: AnyObject?
    private var keyTestTimeoutTask: Task<Void, Never>?

    var isCountingDown: Bool { secondsRemaining != nil }

    /// Marks a key test as running, keeping `runner` alive until `finishKeyTest` or the timeout.
    /// Returns the ID to pass to `finishKeyTest`; results for older or cancelled tests are ignored.
    func beginKeyTest(retaining runner: AnyObject, timeout: TimeInterval = ErrorCardState.keyTestTimeout) -> UUID {
        endKeyTest()
        let id = UUID()
        keyTestID = id
        keyTestRunner = runner
        keyTest = .testing
        keyTestTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.finishKeyTest(id: id, result: .failed("Test failed: no response after \(Int(timeout)) seconds."))
        }
        return id
    }

    func finishKeyTest(id: UUID, result: KeyTest) {
        guard keyTestID == id else { return }
        endKeyTest()
        keyTest = result
    }

    private func endKeyTest() {
        keyTestTimeoutTask?.cancel()
        keyTestTimeoutTask = nil
        keyTestRunner = nil
        keyTestID = nil
    }

    var canRetryAutomatically: Bool { automaticAttempts < ErrorPresentation.maxAutomaticRetries }

    /// Starts a countdown that calls `onFire` when it reaches zero, counting one automatic attempt.
    func startCountdown(seconds: Int, onFire: @escaping @MainActor () -> Void) {
        cancelCountdown()
        guard canRetryAutomatically else { return }
        secondsRemaining = max(seconds, 1)
        countdownTask = Task { @MainActor [weak self] in
            while let self, let remaining = self.secondsRemaining, remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self.secondsRemaining = remaining - 1
            }
            guard let self, !Task.isCancelled else { return }
            self.secondsRemaining = nil
            self.countdownTask = nil
            self.automaticAttempts += 1
            onFire()
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        secondsRemaining = nil
    }

    /// Called when a new error replaces the previous one.
    func errorChanged() {
        cancelCountdown()
        endKeyTest()
        keyTest = .idle
    }

    /// Called when the user sends a new message, so it gets a fresh automatic-retry budget.
    func resetAttempts() {
        cancelCountdown()
        automaticAttempts = 0
    }
}

/// Callbacks the chat provides to an error card. Missing callbacks hide the matching buttons.
struct ErrorCardActions {
    var state: ErrorCardState?
    var retry: (() -> Void)?
    var openSettings: (() -> Void)?
    var testKey: (() -> Void)?
    var modelChoices: [ErrorModelChoice] = []
    var switchModel: ((ErrorModelChoice) -> Void)?
}

// MARK: - Card View

struct ErrorBubbleView: View {
    let error: ErrorMessage
    let actions: ErrorCardActions

    init(error: ErrorMessage, actions: ErrorCardActions) {
        self.error = error
        self.actions = actions
    }

    init(error: ErrorMessage, onRetry: @escaping () -> Void, onIgnore: @escaping () -> Void, onGoToSettings: (() -> Void)?) {
        self.error = error
        self.actions = ErrorCardActions(retry: onRetry, openSettings: onGoToSettings)
    }

    var body: some View {
        ErrorCardContent(error: error, actions: actions, state: actions.state)
    }
}

private struct ErrorCardContent: View {
    let error: ErrorMessage
    let actions: ErrorCardActions
    @ObservedObject private var state: ErrorCardState

    private let hasState: Bool
    private let presentation: ErrorPresentation

    @State private var showDetails = false
    @State private var copiedDetails = false
    @Environment(\.colorScheme) private var colorScheme

    init(error: ErrorMessage, actions: ErrorCardActions, state: ErrorCardState?) {
        self.error = error
        self.actions = actions
        self.hasState = state != nil
        self.state = state ?? ErrorCardState()
        self.presentation = error.presentation
    }

    private var accentColor: Color {
        switch presentation.severity {
        case .transient: return .orange
        case .auth, .quota: return .red
        case .other: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: presentation.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 18)
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(presentation.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(presentation.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                keyTestStatus

                actionRow
                    .padding(.top, 2)

                if !presentation.detailRows.isEmpty {
                    detailsSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.leading, 13)
        .padding(.trailing, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.9 : 1))
        )
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10, style: .continuous)
                .fill(accentColor.opacity(presentation.severity == .other ? 0.5 : 1))
                .frame(width: 3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    // MARK: Actions

    private var showsCountdown: Bool {
        hasState && presentation.retriesAutomatically && state.isCountingDown
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 8) {
            if showsCountdown, let seconds = state.secondsRemaining {
                Text("Retrying in \(seconds)s")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Retrying automatically in \(seconds) seconds")

                if let retry = actions.retry {
                    Button("Retry now") {
                        state.cancelCountdown()
                        retry()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button("Cancel") { state.cancelCountdown() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                if presentation.actions.contains(.retry), let retry = actions.retry {
                    Button {
                        retry()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if presentation.actions.contains(.openSettings), let openSettings = actions.openSettings {
                    Button(settingsLabel, action: openSettings)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                if presentation.actions.contains(.testKey), let testKey = actions.testKey {
                    Button("Test key", action: testKey)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(state.keyTest == .testing)
                }

                if presentation.actions.contains(.testKey), state.keyTest == .succeeded, let retry = actions.retry {
                    Button("Send now", action: retry)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }

            if presentation.actions.contains(.switchModel), !actions.modelChoices.isEmpty,
                let switchModel = actions.switchModel
            {
                Menu {
                    ForEach(actions.modelChoices) { choice in
                        Button("\(choice.modelId) (\(choice.providerName))") {
                            state.cancelCountdown()
                            switchModel(choice)
                        }
                    }
                } label: {
                    Text("Use another model")
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
            }
        }
    }

    private var settingsLabel: String {
        switch presentation.severity {
        case .auth where presentation.providerName != ErrorPresentation.fallbackProviderName,
            .quota where presentation.providerName != ErrorPresentation.fallbackProviderName:
            return "Open \(presentation.providerName) settings"
        default:
            return "Open Settings"
        }
    }

    @ViewBuilder
    private var keyTestStatus: some View {
        if presentation.actions.contains(.testKey) {
            switch state.keyTest {
            case .idle:
                EmptyView()
            case .testing:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Testing key…")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            case .succeeded:
                Label("The key works. Your message is ready to send.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
            case .failed(let reason):
                Label(reason, systemImage: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showDetails.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(showDetails ? 90 : 0))
                    Text("Details")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showDetails ? "Hide error details" : "Show error details")

            if showDetails {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(presentation.detailRows, id: \.label) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(row.label)
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Text(row.value)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(.system(size: 11, design: .monospaced))

                Button {
                    copyDetails()
                } label: {
                    Label(copiedDetails ? "Copied" : "Copy details", systemImage: copiedDetails ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(.top, 2)
    }

    private func copyDetails() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(presentation.detailsText(timestamp: error.timestamp), forType: .string)
        copiedDetails = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedDetails = false
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        ErrorBubbleView(
            error: ErrorMessage(
                apiError: APIError.overloaded.adding(
                    ProviderErrorContext(
                        providerName: "Claude",
                        providerType: "claude",
                        model: "claude-sonnet-4",
                        statusCode: 529,
                        requestID: "req_123",
                        errorType: "overloaded_error",
                        message: "Overloaded"
                    )
                )
            ),
            actions: ErrorCardActions(
                retry: {},
                modelChoices: [ErrorModelChoice(providerType: "chatgpt", providerName: "OpenAI", modelId: "gpt-4o")],
                switchModel: { _ in }
            )
        )

        ErrorBubbleView(
            error: ErrorMessage(
                apiError: APIError.unauthorized.adding(ProviderErrorContext(providerName: "Claude", providerType: "claude"))
            ),
            actions: ErrorCardActions(retry: {}, openSettings: {}, testKey: {})
        )

        ErrorBubbleView(
            error: ErrorMessage(apiError: .requestFailed(URLError(.notConnectedToInternet))),
            actions: ErrorCardActions(retry: {})
        )
    }
    .frame(width: 560)
    .padding()
    .background(Color(.windowBackgroundColor))
}
