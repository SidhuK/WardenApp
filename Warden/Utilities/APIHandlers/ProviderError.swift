import Foundation

/// Diagnostic details attached to an `APIError` coming from a provider.
struct ProviderErrorContext: Equatable, Sendable {
    var providerName: String?
    var providerType: String?
    var model: String?
    var statusCode: Int?
    var requestID: String?
    var retryAfter: TimeInterval?
    var errorType: String?
    /// Human-readable message parsed from the error body.
    var message: String?
    /// Truncated raw error body, kept so compatibility retries can match parameter names
    /// that the parsed message may omit.
    var rawBody: String?

    init(
        providerName: String? = nil,
        providerType: String? = nil,
        model: String? = nil,
        statusCode: Int? = nil,
        requestID: String? = nil,
        retryAfter: TimeInterval? = nil,
        errorType: String? = nil,
        message: String? = nil,
        rawBody: String? = nil
    ) {
        self.providerName = providerName
        self.providerType = providerType
        self.model = model
        self.statusCode = statusCode
        self.requestID = requestID
        self.retryAfter = retryAfter
        self.errorType = errorType
        self.message = message
        self.rawBody = rawBody
    }

    /// Fills fields that are nil here with values from `other`; existing values win.
    func filling(from other: ProviderErrorContext) -> ProviderErrorContext {
        ProviderErrorContext(
            providerName: providerName ?? other.providerName,
            providerType: providerType ?? other.providerType,
            model: model ?? other.model,
            statusCode: statusCode ?? other.statusCode,
            requestID: requestID ?? other.requestID,
            retryAfter: retryAfter ?? other.retryAfter,
            errorType: errorType ?? other.errorType,
            message: message ?? other.message,
            rawBody: rawBody ?? other.rawBody
        )
    }
}

extension APIError {
    /// The underlying error with any provider context removed.
    var base: APIError {
        if case .withContext(let inner, _) = self {
            return inner.base
        }
        return self
    }

    var context: ProviderErrorContext? {
        if case .withContext(let inner, let context) = self {
            if let innerContext = inner.context {
                return context.filling(from: innerContext)
            }
            return context
        }
        return nil
    }

    /// Returns this error with `ctx` merged into its context. Fields already set are kept.
    func adding(_ ctx: ProviderErrorContext) -> APIError {
        if let existing = context {
            return .withContext(base, existing.filling(from: ctx))
        }
        return .withContext(base, ctx)
    }

    /// Text used by compatibility checks: the base message plus the raw provider body when known.
    var compatibilityText: String? {
        var parts: [String] = []
        switch base {
        case .serverError(let message), .unknown(let message), .decodingFailed(let message):
            parts.append(message)
        default:
            break
        }
        if let raw = context?.rawBody {
            parts.append(raw)
        }
        if let message = context?.message {
            parts.append(message)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

enum ProviderErrorBodyParser {
    static let maxFallbackLength = 300

    /// Extracts a human-readable message and error type from a provider error body.
    static func parse(_ data: Data) -> (message: String?, type: String?) {
        if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            let parsed = parse(json: json)
            if parsed.message != nil || parsed.type != nil {
                return parsed
            }
        }

        guard let text = String(data: data, encoding: .utf8) else { return (nil, nil) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, nil) }
        if trimmed.hasPrefix("<") {
            // HTML error pages from proxies are noise; keep only the <title> if present.
            if let title = htmlTitle(trimmed) {
                return (truncate(title), nil)
            }
            return (nil, nil)
        }
        return (truncate(trimmed), nil)
    }

    private static func parse(json: Any) -> (message: String?, type: String?) {
        if let array = json as? [Any] {
            for element in array {
                let parsed = parse(json: element)
                if parsed.message != nil || parsed.type != nil {
                    return parsed
                }
            }
            return (nil, nil)
        }

        if let string = json as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed.isEmpty ? nil : truncate(trimmed), nil)
        }

        guard let dict = json as? [String: Any] else { return (nil, nil) }

        if let error = dict["error"] as? [String: Any] {
            let message = stringValue(error["message"]) ?? stringValue(error["detail"])
            let type = stringValue(error["type"]) ?? stringValue(error["status"]) ?? stringValue(error["code"])
            if message != nil || type != nil {
                return (message.map { truncate($0) }, type)
            }
        }

        if let errorString = stringValue(dict["error"]) {
            let type = stringValue(dict["type"]).flatMap { $0 == "error" ? nil : $0 } ?? stringValue(dict["code"])
            return (truncate(errorString), type)
        }

        if let message = stringValue(dict["message"]) {
            let type = stringValue(dict["type"]).flatMap { $0 == "error" ? nil : $0 } ?? stringValue(dict["code"])
            return (truncate(message), type)
        }

        if let detail = dict["detail"] {
            if let detailString = stringValue(detail) {
                return (truncate(detailString), nil)
            }
            let parsed = parse(json: detail)
            if parsed.message != nil {
                return parsed
            }
            if let detailArray = detail as? [[String: Any]],
               let first = detailArray.first,
               let msg = stringValue(first["msg"]) {
                return (truncate(msg), stringValue(first["type"]))
            }
        }

        return (nil, nil)
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func htmlTitle(_ html: String) -> String? {
        guard let start = html.range(of: "<title>", options: .caseInsensitive),
              let end = html.range(of: "</title>", options: .caseInsensitive, range: start.upperBound..<html.endIndex)
        else { return nil }
        let title = html[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    static func truncate(_ text: String, limit: Int = maxFallbackLength) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

enum ProviderHTTPHeaders {
    private static let requestIDHeaders = [
        "x-request-id",
        "request-id",
        "anthropic-request-id",
        "openai-request-id",
        "x-amzn-requestid",
        "cf-ray",
    ]

    static func requestID(from response: HTTPURLResponse) -> String? {
        for name in requestIDHeaders {
            if let value = response.value(forHTTPHeaderField: name)?.trimmingCharacters(in: .whitespaces),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func retryAfter(from response: HTTPURLResponse, now: Date = Date()) -> TimeInterval? {
        retryAfter(
            retryAfterMs: response.value(forHTTPHeaderField: "retry-after-ms"),
            retryAfter: response.value(forHTTPHeaderField: "Retry-After"),
            now: now
        )
    }

    /// Parses `retry-after-ms` (milliseconds) or `Retry-After` (delta seconds or an HTTP date).
    static func retryAfter(retryAfterMs: String?, retryAfter: String?, now: Date = Date()) -> TimeInterval? {
        if let msString = retryAfterMs?.trimmingCharacters(in: .whitespaces),
           let ms = Double(msString), ms >= 0 {
            return ms / 1000
        }

        guard let raw = retryAfter?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }

        if let seconds = Double(raw) {
            return seconds >= 0 ? seconds : nil
        }

        if let date = httpDateFormatter.date(from: raw) {
            return max(0, date.timeIntervalSince(now))
        }
        return nil
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}

enum ProviderErrorMapper {
    private static let maxRawBodyLength = 2_000

    /// Builds an `APIError` with context for a non-2xx HTTP response.
    static func error(for response: HTTPURLResponse, data: Data?) -> APIError {
        let status = response.statusCode
        let parsed = data.map(ProviderErrorBodyParser.parse) ?? (message: nil, type: nil)
        let rawBody = data.flatMap { String(data: $0, encoding: .utf8) }
            .map { ProviderErrorBodyParser.truncate($0, limit: maxRawBodyLength) }

        let context = ProviderErrorContext(
            statusCode: status,
            requestID: ProviderHTTPHeaders.requestID(from: response),
            retryAfter: ProviderHTTPHeaders.retryAfter(from: response),
            errorType: parsed.type,
            message: parsed.message,
            rawBody: rawBody
        )

        return baseError(status: status, message: parsed.message, type: parsed.type, hasBody: data != nil)
            .adding(context)
    }

    static func baseError(status: Int, message: String?, type: String?, hasBody: Bool = true) -> APIError {
        let detail = message ?? HTTPURLResponse.localizedString(forStatusCode: status).capitalized
        let lowerType = type?.lowercased() ?? ""
        let lowerMessage = message?.lowercased() ?? ""

        if status == 529 || lowerType.contains("overloaded")
            || (status == 503 && lowerMessage.contains("overloaded")) {
            return .overloaded
        }

        switch status {
        case 401, 403:
            return .unauthorized
        case 429:
            return .rateLimited
        case 400...499:
            return .serverError(hasBody ? "Client Error: \(detail)" : "HTTP \(status)")
        case 500...599:
            return .serverError(hasBody ? "Server Error: \(detail)" : "HTTP \(status)")
        default:
            return .unknown("Unknown error: \(detail)")
        }
    }
}
