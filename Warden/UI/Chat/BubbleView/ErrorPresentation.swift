import CoreData
import Foundation

/// How serious an error is, which drives the card's accent color and symbol.
enum ErrorSeverity: Equatable {
    /// Temporary provider or network trouble that usually clears by itself.
    case transient
    /// The API key or credentials were rejected.
    case auth
    /// The account ran out of quota or credits; only a billing change fixes it.
    case quota
    case other
}

/// Actions an error card can offer. The card decides how to render each one.
enum ErrorAction: Equatable {
    case retry
    case openSettings
    case testKey
    case switchModel
}

/// A model the user can switch to from an error card.
struct ErrorModelChoice: Hashable, Identifiable {
    let providerType: String
    let providerName: String
    let modelId: String
    /// The exact service to switch to. Nil for favorites, which are only keyed by provider type.
    var serviceID: NSManagedObjectID? = nil

    var id: String { "\(providerType):\(modelId)" }
}

/// User-facing copy and actions for an error, derived without any UI dependencies.
struct ErrorPresentation: Equatable {
    struct DetailRow: Equatable {
        let label: String
        let value: String
    }

    static let fallbackProviderName = "The provider"
    static let defaultRetryDelay = 10
    static let retryDelayRange = 1...60
    static let maxAutomaticRetries = 3

    let title: String
    let body: String
    let severity: ErrorSeverity
    let symbolName: String
    let actions: [ErrorAction]
    /// True when the error should count down and retry automatically (rate limits and overload).
    let retriesAutomatically: Bool
    /// Seconds to wait before an automatic retry, already clamped to `retryDelayRange`.
    let retryDelay: Int
    /// Provider name for button labels such as "Open Anthropic settings".
    let providerName: String
    let detailRows: [DetailRow]

    var isRetryable: Bool { actions.contains(.retry) }

    // MARK: - Init

    init(error: ErrorMessage) {
        switch error.type {
        case .apiError(let apiError):
            self.init(apiError: apiError)
        case .webSearchError(let webSearchError):
            self.init(webSearchError: webSearchError)
        case .generic(let error):
            self.init(
                title: "Something went wrong",
                body: Self.sanitizedMessage(error.localizedDescription) ?? "An unexpected error occurred.",
                severity: .other,
                actions: [.retry],
                providerName: Self.fallbackProviderName,
                detailRows: []
            )
        }
    }

    init(apiError: APIError) {
        let context = apiError.context
        let provider = Self.providerDisplayName(context: context)
        let model = context?.model.flatMap { $0.isEmpty ? nil : $0 }
        let modelSubject = model ?? "The model"
        let modelObject = model ?? "the model"
        let rows = Self.detailRows(context: context, provider: provider)
        let providerRef = provider == Self.fallbackProviderName ? "the provider" : provider
        let delay = Self.clampedRetryDelay(context?.retryAfter)

        var base = apiError.base
        if case .serverError = base, context?.statusCode == 429 {
            base = .rateLimited
        }
        if case .serverError = base, context?.statusCode == 529 {
            base = .overloaded
        }

        if Self.indicatesQuotaExhausted(apiError) {
            let accountOwner = provider == Self.fallbackProviderName ? "Your" : "Your \(provider)"
            self.init(
                title: "\(accountOwner) quota is used up",
                body: Self.compose(
                    "The account has run out of quota or credits, so waiting won't help. "
                        + "Check billing and credits with \(providerRef), or switch to another API key in Settings.",
                    providerMessage: Self.providerMessage(apiError),
                    provider: provider
                ),
                severity: .quota,
                actions: [.openSettings, .retry],
                providerName: provider,
                detailRows: rows
            )
            return
        }

        switch base {
        case .rateLimited:
            self.init(
                title: "\(provider) is rate-limiting requests",
                body: Self.compose(
                    "Too many requests were sent to \(modelObject) in a short time. "
                        + "This usually clears within a few seconds.",
                    providerMessage: Self.providerMessage(apiError),
                    provider: provider
                ),
                severity: .transient,
                actions: [.retry],
                retriesAutomatically: true,
                retryDelay: delay,
                providerName: provider,
                detailRows: rows
            )

        case .overloaded:
            self.init(
                title: "\(provider) is overloaded",
                body: Self.compose(
                    "\(modelSubject) is temporarily over capacity on \(providerRef)'s side. "
                        + "It usually recovers quickly, or you can switch to another model.",
                    providerMessage: Self.providerMessage(apiError),
                    provider: provider
                ),
                severity: .transient,
                actions: [.retry, .switchModel],
                retriesAutomatically: true,
                retryDelay: delay,
                providerName: provider,
                detailRows: rows
            )

        case .unauthorized:
            let keyOwner = provider == Self.fallbackProviderName ? "Your" : "Your \(provider)"
            self.init(
                title: "\(keyOwner) API key was rejected",
                body: Self.compose(
                    "The key is missing, invalid, or doesn't have access to "
                        + "\(model ?? "this model"). Check it in Settings, then send your message again.",
                    providerMessage: Self.providerMessage(apiError),
                    provider: provider
                ),
                severity: .auth,
                actions: [.openSettings, .testKey],
                providerName: provider,
                detailRows: rows
            )

        case .requestFailed(let underlying):
            let reason = Self.sanitizedMessage(underlying.localizedDescription)
            let lead = reason.map { Self.sentence($0) + " " } ?? ""
            self.init(
                title: "Couldn't reach \(providerRef)",
                body: lead + "Check your internet connection and the service URL, then try again.",
                severity: .transient,
                actions: [.retry],
                providerName: provider,
                detailRows: rows
            )

        case .serverError(let message):
            let status = context?.statusCode ?? Self.statusCode(fromHTTPMessage: message)
            let isServerSide = status.map { $0 >= 500 } ?? message.hasPrefix("Server Error")
            let parsed = Self.providerMessage(apiError) ?? Self.sanitizedMessage(message)
            if isServerSide {
                let statusText = status.map { " (HTTP \($0))" } ?? ""
                self.init(
                    title: "\(provider) returned an error",
                    body: Self.compose(
                        "\(provider) had a problem handling the request\(statusText). "
                            + "This is usually temporary.",
                        providerMessage: parsed,
                        provider: provider
                    ),
                    severity: .other,
                    actions: [.retry, .switchModel],
                    providerName: provider,
                    detailRows: rows
                )
            } else {
                self.init(
                    title: "\(provider) returned an error",
                    body: parsed.map { Self.sentence($0) }
                        ?? "\(provider) couldn't process the request for \(modelObject).",
                    severity: .other,
                    actions: [.retry],
                    providerName: provider,
                    detailRows: rows
                )
            }

        case .invalidResponse:
            self.init(
                title: "\(provider) sent an unexpected response",
                body: "The response couldn't be understood. Trying again often helps.",
                severity: .other,
                actions: [.retry],
                providerName: provider,
                detailRows: rows
            )

        case .decodingFailed(let message):
            let detail = Self.providerMessage(apiError) ?? Self.sanitizedMessage(message)
            self.init(
                title: "Couldn't read \(providerRef)'s response",
                body: Self.compose(
                    "The response arrived but couldn't be processed.",
                    providerMessage: detail,
                    provider: nil
                ),
                severity: .other,
                actions: [.retry],
                providerName: provider,
                detailRows: rows
            )

        case .noApiService(let message):
            self.init(
                title: "No AI service is selected",
                body: Self.sanitizedMessage(message).map { Self.sentence($0) }
                    ?? "Add or select an API service in Settings to start chatting.",
                severity: .other,
                actions: [.openSettings],
                providerName: provider,
                detailRows: rows
            )

        case .unknown(let message):
            let detail = Self.providerMessage(apiError) ?? Self.sanitizedMessage(message)
            self.init(
                title: "\(provider) returned an error",
                body: detail.map { Self.sentence($0) } ?? "An unexpected error occurred.",
                severity: .other,
                actions: [.retry],
                providerName: provider,
                detailRows: rows
            )

        case .withContext:
            self.init(
                title: "\(provider) returned an error",
                body: Self.providerMessage(apiError).map { Self.sentence($0) } ?? "An unexpected error occurred.",
                severity: .other,
                actions: [.retry],
                providerName: provider,
                detailRows: rows
            )
        }
    }

    init(webSearchError: WebSearchError) {
        let isAuth: Bool
        switch webSearchError {
        case .noApiKey, .unauthorized: isAuth = true
        default: isAuth = false
        }
        self.init(
            title: isAuth ? "Web search needs an API key" : "Web search failed",
            body: webSearchError.errorDescription ?? "An error occurred during search.",
            severity: isAuth ? .auth : .other,
            actions: isAuth ? [.openSettings] : [.retry],
            providerName: "Web search",
            detailRows: []
        )
    }

    private init(
        title: String,
        body: String,
        severity: ErrorSeverity,
        actions: [ErrorAction],
        retriesAutomatically: Bool = false,
        retryDelay: Int = ErrorPresentation.defaultRetryDelay,
        providerName: String,
        detailRows: [DetailRow]
    ) {
        self.title = title
        self.body = body
        self.severity = severity
        self.actions = actions
        self.retriesAutomatically = retriesAutomatically
        self.retryDelay = retryDelay
        self.providerName = providerName
        self.detailRows = detailRows
        switch severity {
        case .transient: symbolName = "clock.arrow.circlepath"
        case .auth: symbolName = "key.slash"
        case .quota: symbolName = "creditcard.trianglebadge.exclamationmark"
        case .other: symbolName = "exclamationmark.triangle"
        }
    }

    // MARK: - Details

    /// Plain-text block for "Copy details". Never contains API keys or headers other than the request ID.
    func detailsText(timestamp: Date? = nil) -> String {
        var lines = ["\(title)"]
        lines.append(contentsOf: detailRows.map { "\($0.label): \($0.value)" })
        if let timestamp {
            lines.append("Time: \(ISO8601DateFormatter().string(from: timestamp))")
        }
        return lines.joined(separator: "\n")
    }

    private static func detailRows(context: ProviderErrorContext?, provider: String) -> [DetailRow] {
        guard let context else { return [] }
        var rows: [DetailRow] = []
        var providerValue = context.providerName ?? provider
        if let type = context.providerType, !type.isEmpty, type != providerValue {
            providerValue += " (\(type))"
        }
        if context.providerName != nil || context.providerType != nil {
            rows.append(DetailRow(label: "Provider", value: providerValue))
        }
        if let model = context.model, !model.isEmpty {
            rows.append(DetailRow(label: "Model", value: model))
        }
        if let status = context.statusCode {
            rows.append(DetailRow(label: "Status", value: String(status)))
        }
        if let type = context.errorType, !type.isEmpty {
            rows.append(DetailRow(label: "Error type", value: type))
        }
        if let requestID = context.requestID, !requestID.isEmpty {
            rows.append(DetailRow(label: "Request ID", value: requestID))
        }
        if let retryAfter = context.retryAfter,
           let seconds = roundedRetrySeconds(retryAfter, upperBound: Double(Int32.max)) {
            rows.append(DetailRow(label: "Retry after", value: "\(seconds)s"))
        }
        if let message = sanitizedMessage(context.message) {
            rows.append(DetailRow(label: "Message", value: message))
        }
        return rows
    }

    // MARK: - Helpers

    private static let vendorNames: [String: String] = [
        "chatgpt": "OpenAI",
        "claude": "Anthropic",
        "gemini": "Google Gemini",
        "google": "Google",
        "deepseek": "DeepSeek",
        "mistral": "Mistral",
        "perplexity": "Perplexity",
        "openrouter": "OpenRouter",
        "ollama": "Ollama",
        "lmstudio": "LM Studio",
        "groq": "Groq",
        "xai": "xAI",
    ]

    /// Vendor name for well-known provider types, otherwise the service's own name.
    static func providerDisplayName(context: ProviderErrorContext?) -> String {
        if let type = context?.providerType?.lowercased(), let vendor = vendorNames[type] {
            return vendor
        }
        if let name = context?.providerName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let type = context?.providerType, let name = AppConstants.defaultApiConfigurations[type]?.name {
            return name
        }
        return fallbackProviderName
    }

    private static let quotaErrorTypes: Set<String> = [
        "insufficient_quota",
        "quota_exceeded",
        "insufficient_balance",
        "billing_hard_limit_reached",
        "billing_not_active",
    ]

    private static let quotaMarkers = [
        "insufficient_quota",
        "quota_exceeded",
        "quota exceeded",
        "exceeded your current quota",
        "credit balance",
        "insufficient credits",
        "out of credits",
        "insufficient_balance",
        "insufficient balance",
    ]

    /// Phrases used by temporary rate limits. OpenAI's RPM/TPM messages also link to the billing page,
    /// so these win over message-based quota markers.
    private static let rateLimitMarkers = ["per minute", "per min", "try again in"]

    /// True when the error type or message says the account is out of quota, billing or credits.
    /// Per-minute quota messages (e.g. Gemini's RESOURCE_EXHAUSTED) are ordinary rate limits.
    static func indicatesQuotaExhausted(_ error: APIError) -> Bool {
        if let type = error.context?.errorType?.lowercased(), quotaErrorTypes.contains(type) {
            return true
        }
        var texts = [error.context?.errorType, error.context?.message]
        switch error.base {
        case .serverError(let message), .unknown(let message):
            texts.append(message)
        default:
            break
        }
        let lower = texts.compactMap { $0?.lowercased() }
        guard !lower.contains(where: { text in rateLimitMarkers.contains { text.contains($0) } }) else {
            return false
        }
        return lower.contains { text in quotaMarkers.contains { text.contains($0) } }
    }

    /// Whole seconds for a Retry-After value, clamped in floating point so huge values can't trap on `Int(_:)`.
    static func roundedRetrySeconds(_ retryAfter: TimeInterval, upperBound: Double) -> Int? {
        guard retryAfter.isFinite else { return nil }
        return Int(min(max(retryAfter.rounded(.up), 0), upperBound))
    }

    static func clampedRetryDelay(_ retryAfter: TimeInterval?) -> Int {
        guard let retryAfter,
              let seconds = roundedRetrySeconds(retryAfter, upperBound: Double(retryDelayRange.upperBound))
        else { return defaultRetryDelay }
        return min(max(seconds, retryDelayRange.lowerBound), retryDelayRange.upperBound)
    }

    private static func providerMessage(_ error: APIError) -> String? {
        sanitizedMessage(error.context?.message)
    }

    private static let wrapperPrefixes = ["Client Error:", "Server Error:", "Unknown error:", "Failed to process response:"]

    /// Cleans a message for display. Strips internal prefixes and turns JSON bodies into their message,
    /// returning nil when nothing readable remains.
    static func sanitizedMessage(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        for prefix in wrapperPrefixes where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let jsonStart = text.firstIndex(where: { $0 == "{" || $0 == "[" }) {
            let candidate = String(text[jsonStart...])
            let isJSON = (try? JSONSerialization.jsonObject(with: Data(candidate.utf8))) != nil
            if isJSON || jsonStart == text.startIndex {
                let parsed = ProviderErrorBodyParser.parse(Data(candidate.utf8)).message
                if let parsed, !parsed.hasPrefix("{"), !parsed.hasPrefix("[") {
                    return parsed
                }
                let leading = text[..<jsonStart].trimmingCharacters(in: CharacterSet(charactersIn: " :-\n"))
                return leading.isEmpty ? nil : leading
            }
        }
        return text.isEmpty ? nil : text
    }

    private static func statusCode(fromHTTPMessage message: String) -> Int? {
        guard message.hasPrefix("HTTP ") else { return nil }
        return Int(message.dropFirst(5).prefix(3))
    }

    private static func compose(_ lead: String, providerMessage: String?, provider: String?) -> String {
        guard let providerMessage, !providerMessage.isEmpty else { return lead }
        let quoted = "“\(sentence(providerMessage))”"
        if let provider, provider != fallbackProviderName {
            return "\(lead)\n\(provider) said: \(quoted)"
        }
        return "\(lead)\n\(quoted)"
    }

    private static func sentence(_ text: String) -> String {
        guard let last = text.last, !".!?…".contains(last) else { return text }
        return text + "."
    }

    // MARK: - Alternative models

    /// Models to offer in "Use another model": favorites with a configured service, excluding the current model.
    /// Falls back to the default model of every other configured service when there are no usable favorites.
    static func alternativeModels(
        favorites: [(provider: String, model: String)],
        services: [(type: String, name: String, model: String?, id: NSManagedObjectID?)],
        currentProviderType: String?,
        currentModel: String?
    ) -> [ErrorModelChoice] {
        let configuredTypes = Set(services.map(\.type))
        func name(for type: String) -> String {
            vendorNames[type] ?? services.first(where: { $0.type == type })?.name ?? type
        }
        func isCurrent(_ type: String, _ model: String) -> Bool {
            type == currentProviderType && model == currentModel
        }

        var seen = Set<String>()
        let fromFavorites = favorites
            .filter { configuredTypes.contains($0.provider) && !isCurrent($0.provider, $0.model) }
            .sorted { ($0.provider, $0.model) < ($1.provider, $1.model) }
            .map { ErrorModelChoice(providerType: $0.provider, providerName: name(for: $0.provider), modelId: $0.model) }
            .filter { seen.insert($0.id).inserted }
        if !fromFavorites.isEmpty { return fromFavorites }

        return services
            .filter { $0.type != currentProviderType }
            .compactMap { service -> ErrorModelChoice? in
                guard let model = service.model, !model.isEmpty else { return nil }
                return ErrorModelChoice(
                    providerType: service.type,
                    providerName: name(for: service.type),
                    modelId: model,
                    serviceID: service.id
                )
            }
            .filter { seen.insert($0.id).inserted }
    }
}
