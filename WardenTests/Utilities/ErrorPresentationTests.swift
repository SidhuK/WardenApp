import XCTest
@testable import Warden

final class ErrorPresentationTests: XCTestCase {
    private func anthropic(
        status: Int? = nil,
        retryAfter: TimeInterval? = nil,
        errorType: String? = nil,
        message: String? = nil,
        requestID: String? = nil
    ) -> ProviderErrorContext {
        ProviderErrorContext(
            providerName: "Claude",
            providerType: "claude",
            model: "claude-sonnet-4",
            statusCode: status,
            requestID: requestID,
            retryAfter: retryAfter,
            errorType: errorType,
            message: message
        )
    }

    // MARK: - Cases

    func testRateLimited() {
        let p = ErrorPresentation(apiError: APIError.rateLimited.adding(anthropic(status: 429, retryAfter: 8)))
        XCTAssertEqual(p.title, "Anthropic is rate-limiting requests")
        XCTAssertEqual(p.severity, .transient)
        XCTAssertEqual(p.actions, [.retry])
        XCTAssertTrue(p.retriesAutomatically)
        XCTAssertEqual(p.retryDelay, 8)
        XCTAssertTrue(p.body.contains("claude-sonnet-4"))
    }

    func testOverloaded() {
        let p = ErrorPresentation(
            apiError: APIError.overloaded.adding(anthropic(status: 529, errorType: "overloaded_error", message: "Overloaded"))
        )
        XCTAssertEqual(p.title, "Anthropic is overloaded")
        XCTAssertEqual(p.severity, .transient)
        XCTAssertEqual(p.actions, [.retry, .switchModel])
        XCTAssertTrue(p.retriesAutomatically)
        XCTAssertEqual(p.retryDelay, ErrorPresentation.defaultRetryDelay)
        XCTAssertTrue(p.body.contains("Overloaded"))
    }

    func testInsufficientQuota429DoesNotAutoRetry() {
        let context = ProviderErrorContext(
            providerName: "OpenAI",
            providerType: "chatgpt",
            model: "gpt-4o",
            statusCode: 429,
            errorType: "insufficient_quota",
            message: "You exceeded your current quota, please check your plan and billing details."
        )
        let p = ErrorPresentation(apiError: APIError.rateLimited.adding(context))
        XCTAssertEqual(p.title, "Your OpenAI quota is used up")
        XCTAssertEqual(p.severity, .quota)
        XCTAssertFalse(p.retriesAutomatically)
        XCTAssertEqual(p.actions, [.openSettings, .retry])
        XCTAssertTrue(p.body.lowercased().contains("credits"))
    }

    func testCreditBalanceMessageIsQuota() {
        let p = ErrorPresentation(
            apiError: APIError.serverError("Client Error: Your credit balance is too low")
                .adding(anthropic(status: 400, errorType: "invalid_request_error", message: "Your credit balance is too low"))
        )
        XCTAssertEqual(p.title, "Your Anthropic quota is used up")
        XCTAssertFalse(p.retriesAutomatically)
    }

    func testPerMinuteQuotaStaysRateLimited() {
        let context = ProviderErrorContext(
            providerType: "gemini",
            statusCode: 429,
            errorType: "RESOURCE_EXHAUSTED",
            message: "Quota exceeded for metric: generate_content requests per minute"
        )
        let p = ErrorPresentation(apiError: APIError.rateLimited.adding(context))
        XCTAssertEqual(p.severity, .transient)
        XCTAssertTrue(p.retriesAutomatically)
    }

    func testStatus529ServerErrorIsTreatedAsOverloaded() {
        let p = ErrorPresentation(apiError: APIError.serverError("Server Error: busy").adding(anthropic(status: 529)))
        XCTAssertEqual(p.title, "Anthropic is overloaded")
        XCTAssertTrue(p.retriesAutomatically)
    }

    func testUnauthorized() {
        let p = ErrorPresentation(
            apiError: APIError.unauthorized.adding(anthropic(status: 401, message: "invalid x-api-key"))
        )
        XCTAssertEqual(p.title, "Your Anthropic API key was rejected")
        XCTAssertEqual(p.severity, .auth)
        XCTAssertEqual(p.actions, [.openSettings, .testKey])
        XCTAssertFalse(p.retriesAutomatically)
        XCTAssertFalse(p.isRetryable)
        XCTAssertTrue(p.body.contains("invalid x-api-key"))
    }

    func testServerError5xx() {
        let p = ErrorPresentation(
            apiError: APIError.serverError("Server Error: Internal").adding(anthropic(status: 500, message: "Internal"))
        )
        XCTAssertEqual(p.title, "Anthropic returned an error")
        XCTAssertEqual(p.severity, .other)
        XCTAssertEqual(p.actions, [.retry, .switchModel])
        XCTAssertFalse(p.retriesAutomatically)
        XCTAssertTrue(p.body.contains("HTTP 500"))
    }

    func testClientError4xxUsesParsedMessage() {
        let p = ErrorPresentation(
            apiError: APIError.serverError("Client Error: max_tokens too large")
                .adding(anthropic(status: 400, message: "max_tokens too large"))
        )
        XCTAssertEqual(p.title, "Anthropic returned an error")
        XCTAssertEqual(p.actions, [.retry])
        XCTAssertEqual(p.body, "max_tokens too large.")
    }

    func testRequestFailed() {
        let p = ErrorPresentation(
            apiError: APIError.requestFailed(URLError(.notConnectedToInternet)).adding(anthropic())
        )
        XCTAssertEqual(p.title, "Couldn't reach Anthropic")
        XCTAssertEqual(p.severity, .transient)
        XCTAssertEqual(p.actions, [.retry])
        XCTAssertFalse(p.retriesAutomatically)
    }

    func testNoApiService() {
        let p = ErrorPresentation(apiError: .noApiService("No API service selected"))
        XCTAssertEqual(p.title, "No AI service is selected")
        XCTAssertEqual(p.actions, [.openSettings])
    }

    func testWebSearchAuthError() {
        let p = ErrorPresentation(error: ErrorMessage(webSearchError: .noApiKey))
        XCTAssertEqual(p.severity, .auth)
        XCTAssertEqual(p.actions, [.openSettings])
    }

    // MARK: - Provider naming

    func testProviderFallback() {
        let p = ErrorPresentation(apiError: .rateLimited)
        XCTAssertEqual(p.title, "The provider is rate-limiting requests")
        XCTAssertEqual(
            ErrorPresentation(apiError: .unauthorized).title,
            "Your API key was rejected"
        )
        XCTAssertEqual(ErrorPresentation(apiError: .requestFailed(URLError(.timedOut))).title, "Couldn't reach the provider")
    }

    func testCustomServiceUsesServiceName() {
        let ctx = ProviderErrorContext(providerName: "Work Proxy", providerType: "openai_custom")
        XCTAssertEqual(ErrorPresentation(apiError: APIError.overloaded.adding(ctx)).title, "Work Proxy is overloaded")
    }

    // MARK: - Retry-After

    func testRetryAfterClamp() {
        XCTAssertEqual(ErrorPresentation.clampedRetryDelay(nil), 10)
        XCTAssertEqual(ErrorPresentation.clampedRetryDelay(0), 1)
        XCTAssertEqual(ErrorPresentation.clampedRetryDelay(0.2), 1)
        XCTAssertEqual(ErrorPresentation.clampedRetryDelay(7.5), 8)
        XCTAssertEqual(ErrorPresentation.clampedRetryDelay(600), 60)
        XCTAssertEqual(ErrorPresentation.clampedRetryDelay(-5), 1)
        XCTAssertEqual(ErrorPresentation.clampedRetryDelay(.infinity), 10)
        XCTAssertEqual(ErrorPresentation.clampedRetryDelay(1e20), 60)
        XCTAssertEqual(ErrorPresentation.clampedRetryDelay(.nan), 10)
    }

    func testHugeRetryAfterDoesNotCrashDetails() {
        let huge = ErrorPresentation(apiError: APIError.rateLimited.adding(anthropic(status: 429, retryAfter: 1e20)))
        XCTAssertEqual(huge.retryDelay, 60)
        XCTAssertTrue(huge.detailRows.contains { $0.label == "Retry after" })
        let infinite = ErrorPresentation(apiError: APIError.rateLimited.adding(anthropic(status: 429, retryAfter: .infinity)))
        XCTAssertEqual(infinite.retryDelay, ErrorPresentation.defaultRetryDelay)
        XCTAssertFalse(infinite.detailRows.contains { $0.label == "Retry after" })
        XCTAssertNil(ProviderHTTPHeaders.retryAfter(retryAfterMs: nil, retryAfter: "inf"))
        XCTAssertNil(ProviderHTTPHeaders.retryAfter(retryAfterMs: "nan", retryAfter: nil))
    }

    func testOpenAIRequestsPerMinuteStaysRateLimited() {
        let context = ProviderErrorContext(
            providerName: "OpenAI",
            providerType: "chatgpt",
            model: "gpt-4o",
            statusCode: 429,
            errorType: "requests",
            message: "Rate limit reached for gpt-4o in organization org-abc on requests per min (RPM): Limit 3, "
                + "Used 3, Requested 1. Please try again in 20s. Visit https://platform.openai.com/account/rate-limits "
                + "to learn more. You can increase your rate limit by adding a payment method to your account at "
                + "https://platform.openai.com/account/billing."
        )
        let p = ErrorPresentation(apiError: APIError.rateLimited.adding(context))
        XCTAssertEqual(p.severity, .transient)
        XCTAssertTrue(p.retriesAutomatically)
    }

    // MARK: - No raw JSON

    func testRawJSONNeverShownAsBody() {
        let raw = #"{"type":"error","error":{"type":"invalid_request_error","message":"prompt is too long"}}"#
        let p = ErrorPresentation(apiError: .serverError("Client Error: \(raw)"))
        XCTAssertFalse(p.body.contains("{"))
        XCTAssertTrue(p.body.contains("prompt is too long"))

        let unknown = ErrorPresentation(apiError: .unknown(raw))
        XCTAssertFalse(unknown.body.contains("{"))
        XCTAssertTrue(unknown.body.contains("prompt is too long"))
    }

    func testUnparseableJSONFallsBackToPlainText() {
        let p = ErrorPresentation(apiError: .unknown(#"{"foo":1}"#))
        XCTAssertFalse(p.body.contains("{"))
        XCTAssertFalse(p.body.isEmpty)
    }

    func testSanitizedMessageKeepsBracketsInProse() {
        XCTAssertEqual(ErrorPresentation.sanitizedMessage("Invalid value [abc] for model"), "Invalid value [abc] for model")
        XCTAssertNil(ErrorPresentation.sanitizedMessage("   "))
    }

    // MARK: - Details

    func testCopyDetailsText() {
        let error = APIError.overloaded.adding(
            anthropic(status: 529, retryAfter: 4, errorType: "overloaded_error", message: "Overloaded", requestID: "req_42")
        )
        let p = ErrorPresentation(apiError: error)
        let text = p.detailsText(timestamp: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(
            text,
            """
            Anthropic is overloaded
            Provider: Claude (claude)
            Model: claude-sonnet-4
            Status: 529
            Error type: overloaded_error
            Request ID: req_42
            Retry after: 4s
            Message: Overloaded
            Time: 1970-01-01T00:00:00Z
            """
        )
    }

    func testDetailsOmitRawBody() {
        var ctx = anthropic(status: 401)
        ctx.rawBody = #"{"secret":"sk-ant-123"}"#
        let p = ErrorPresentation(apiError: APIError.unauthorized.adding(ctx))
        XCTAssertFalse(p.detailsText().contains("sk-ant"))
    }

    // MARK: - Alternative models

    func testAlternativeModelsPreferFavoritesExcludingCurrent() {
        let choices = ErrorPresentation.alternativeModels(
            favorites: [
                (provider: "claude", model: "claude-sonnet-4"),
                (provider: "chatgpt", model: "gpt-4o"),
                (provider: "groq", model: "llama"),  // no configured service
            ],
            services: [
                (type: "claude", name: "Claude", model: "claude-sonnet-4", id: nil),
                (type: "chatgpt", name: "OpenAI", model: "gpt-4o-mini", id: nil),
            ],
            currentProviderType: "claude",
            currentModel: "claude-sonnet-4"
        )
        XCTAssertEqual(choices.map(\.id), ["chatgpt:gpt-4o"])
        XCTAssertEqual(choices.first?.providerName, "OpenAI")
    }

    func testAlternativeModelsFallBackToOtherServices() {
        let choices = ErrorPresentation.alternativeModels(
            favorites: [],
            services: [
                (type: "claude", name: "Claude", model: "claude-sonnet-4", id: nil),
                (type: "chatgpt", name: "OpenAI", model: "gpt-4o-mini", id: nil),
                (type: "ollama", name: "Ollama", model: nil, id: nil),
            ],
            currentProviderType: "claude",
            currentModel: "claude-sonnet-4"
        )
        XCTAssertEqual(choices.map(\.id), ["chatgpt:gpt-4o-mini"])
    }

    func testAlternativeModelsEmptyWhenNothingElse() {
        let choices = ErrorPresentation.alternativeModels(
            favorites: [],
            services: [(type: "claude", name: "Claude", model: "claude-sonnet-4", id: nil)],
            currentProviderType: "claude",
            currentModel: "claude-sonnet-4"
        )
        XCTAssertTrue(choices.isEmpty)
    }

    // MARK: - Retry budget

    @MainActor
    func testAutomaticRetryBudget() async {
        let state = ErrorCardState()
        XCTAssertTrue(state.canRetryAutomatically)
        for _ in 0..<ErrorPresentation.maxAutomaticRetries {
            let fired = expectation(description: "fired")
            state.startCountdown(seconds: 1) { fired.fulfill() }
            XCTAssertEqual(state.secondsRemaining, 1)
            await fulfillment(of: [fired], timeout: 3)
        }
        XCTAssertFalse(state.canRetryAutomatically)
        state.startCountdown(seconds: 1) { XCTFail("Should not fire after budget is used") }
        XCTAssertNil(state.secondsRemaining)
        state.resetAttempts()
        XCTAssertTrue(state.canRetryAutomatically)
    }

    @MainActor
    func testCancelStopsCountdown() async throws {
        let state = ErrorCardState()
        state.startCountdown(seconds: 1) { XCTFail("Cancelled countdown fired") }
        state.cancelCountdown()
        XCTAssertNil(state.secondsRemaining)
        try await Task.sleep(nanoseconds: 1_300_000_000)
        XCTAssertEqual(state.automaticAttempts, 0)
    }
}
