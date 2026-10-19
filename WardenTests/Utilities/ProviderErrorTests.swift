import XCTest
@testable import Warden

final class ProviderErrorBodyParserTests: XCTestCase {
    private func parse(_ string: String) -> (message: String?, type: String?) {
        ProviderErrorBodyParser.parse(Data(string.utf8))
    }

    func testOpenAIShape() {
        let result = parse(
            #"{"error":{"message":"Incorrect API key provided","type":"invalid_request_error","code":"invalid_api_key"}}"#
        )
        XCTAssertEqual(result.message, "Incorrect API key provided")
        XCTAssertEqual(result.type, "invalid_request_error")
    }

    func testAnthropicShape() {
        let result = parse(#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)
        XCTAssertEqual(result.message, "Overloaded")
        XCTAssertEqual(result.type, "overloaded_error")
    }

    func testGeminiShape() {
        let result = parse(#"{"error":{"code":429,"message":"Resource has been exhausted","status":"RESOURCE_EXHAUSTED"}}"#)
        XCTAssertEqual(result.message, "Resource has been exhausted")
        XCTAssertEqual(result.type, "RESOURCE_EXHAUSTED")
    }

    func testArrayOfErrors() {
        let result = parse(#"[{"error":{"code":400,"message":"Bad model","status":"INVALID_ARGUMENT"}}]"#)
        XCTAssertEqual(result.message, "Bad model")
        XCTAssertEqual(result.type, "INVALID_ARGUMENT")
    }

    func testPlainMessageAndDetail() {
        XCTAssertEqual(parse(#"{"message":"Model not found"}"#).message, "Model not found")
        XCTAssertEqual(parse(#"{"detail":"Not authenticated"}"#).message, "Not authenticated")
        XCTAssertEqual(parse(#"{"error":"model 'x' not found"}"#).message, "model 'x' not found")
    }

    func testNonJSONFallbackIsTrimmedAndTruncated() {
        XCTAssertEqual(parse("  Bad Gateway \n").message, "Bad Gateway")

        let long = String(repeating: "a", count: 1_000)
        let message = parse(long).message ?? ""
        XCTAssertLessThanOrEqual(message.count, ProviderErrorBodyParser.maxFallbackLength + 1)
        XCTAssertTrue(message.hasSuffix("…"))
    }

    func testHTMLUsesTitle() {
        let result = parse("<html><head><title>502 Bad Gateway</title></head><body>nginx</body></html>")
        XCTAssertEqual(result.message, "502 Bad Gateway")
    }

    func testEmptyBody() {
        XCTAssertNil(parse("").message)
    }
}

final class ProviderErrorMappingTests: XCTestCase {
    private func response(status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com/v1/chat")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    func testRetryAfterSeconds() {
        XCTAssertEqual(ProviderHTTPHeaders.retryAfter(retryAfterMs: nil, retryAfter: "12"), 12)
    }

    func testRetryAfterMillisecondsTakesPrecedence() {
        XCTAssertEqual(ProviderHTTPHeaders.retryAfter(retryAfterMs: "1500", retryAfter: "12"), 1.5)
    }

    func testRetryAfterHTTPDate() throws {
        let now = Date(timeIntervalSince1970: 1_445_412_480)  // Wed, 21 Oct 2015 07:28:00 GMT
        let value = ProviderHTTPHeaders.retryAfter(
            retryAfterMs: nil,
            retryAfter: "Wed, 21 Oct 2015 07:28:30 GMT",
            now: now
        )
        XCTAssertEqual(try XCTUnwrap(value), 30, accuracy: 0.001)
    }

    func testRetryAfterInvalid() {
        XCTAssertNil(ProviderHTTPHeaders.retryAfter(retryAfterMs: nil, retryAfter: "soon"))
        XCTAssertNil(ProviderHTTPHeaders.retryAfter(retryAfterMs: nil, retryAfter: nil))
    }

    func testRateLimitWithHeaders() {
        let error = ProviderErrorMapper.error(
            for: response(status: 429, headers: ["Retry-After": "7", "x-request-id": "req_123"]),
            data: Data(#"{"error":{"message":"Slow down","type":"rate_limit_error"}}"#.utf8)
        )
        guard case .rateLimited = error.base else { return XCTFail("Expected rateLimited, got \(error)") }
        XCTAssertEqual(error.context?.statusCode, 429)
        XCTAssertEqual(error.context?.retryAfter, 7)
        XCTAssertEqual(error.context?.requestID, "req_123")
        XCTAssertEqual(error.context?.message, "Slow down")
        XCTAssertEqual(error.context?.errorType, "rate_limit_error")
    }

    func testAnthropicRequestIDHeader() {
        let error = ProviderErrorMapper.error(
            for: response(status: 500, headers: ["anthropic-request-id": "req_abc"]),
            data: Data("oops".utf8)
        )
        XCTAssertEqual(error.context?.requestID, "req_abc")
        guard case .serverError(let message) = error.base else { return XCTFail("Expected serverError") }
        XCTAssertEqual(message, "Server Error: oops")
    }

    func testOverloadedMapping() {
        let anthropic = ProviderErrorMapper.error(
            for: response(status: 529),
            data: Data(#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#.utf8)
        )
        guard case .overloaded = anthropic.base else { return XCTFail("Expected overloaded") }

        let unavailable = ProviderErrorMapper.error(
            for: response(status: 503),
            data: Data(#"{"error":{"message":"The model is overloaded. Please try again later."}}"#.utf8)
        )
        guard case .overloaded = unavailable.base else { return XCTFail("Expected overloaded for 503") }
    }

    func testUnauthorizedMapping() {
        for status in [401, 403] {
            let error = ProviderErrorMapper.error(for: response(status: status), data: Data("{}".utf8))
            guard case .unauthorized = error.base else { return XCTFail("Expected unauthorized for \(status)") }
        }
    }

    func testClientErrorUsesParsedMessageNotRawJSON() {
        let error = ProviderErrorMapper.error(
            for: response(status: 400),
            data: Data(#"{"error":{"message":"Unrecognized request argument supplied: reasoning_effort"}}"#.utf8)
        )
        guard case .serverError(let message) = error.base else { return XCTFail("Expected serverError") }
        XCTAssertEqual(message, "Client Error: Unrecognized request argument supplied: reasoning_effort")
    }

    func testAddingKeepsExistingContextAndFillsMissing() {
        let error = APIError.rateLimited
            .adding(ProviderErrorContext(statusCode: 429, message: "Slow down"))
            .adding(ProviderErrorContext(providerName: "OpenAI", model: "gpt-4o", statusCode: 500))
        guard case .rateLimited = error.base else { return XCTFail("Expected rateLimited") }
        XCTAssertEqual(error.context?.statusCode, 429)
        XCTAssertEqual(error.context?.providerName, "OpenAI")
        XCTAssertEqual(error.context?.model, "gpt-4o")
        if case .withContext(let inner, _) = error, case .withContext = inner {
            XCTFail("Context should not nest")
        }
    }

    func testCompatibilityRetryStillMatchesWithContext() {
        let error = ProviderErrorMapper.error(
            for: response(status: 400),
            data: Data(#"{"error":{"message":"Unknown parameter","param":"stream_options"}}"#.utf8)
        )
        XCTAssertTrue(
            StreamUsageCompatibility.shouldRetryWithoutStreamUsage(settings: GenerationSettings(temperature: 1), error: error)
        )

        let reasoning = ProviderErrorMapper.error(
            for: response(status: 400),
            data: Data(#"{"error":{"message":"Unrecognized request argument supplied: reasoning_effort"}}"#.utf8)
        )
        XCTAssertTrue(
            ReasoningCompatibility.shouldRetryWithoutReasoning(
                settings: GenerationSettings(temperature: 1, reasoningEffort: .high),
                error: reasoning
            )
        )
    }
}
