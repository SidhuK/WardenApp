import XCTest
@testable import Warden

final class UsageExtractorTests: XCTestCase {
    private func usage(_ json: String) -> TokenUsage? {
        UsageExtractor.usage(from: Data(json.utf8))
    }

    func testOpenAIFinalStreamChunkWithEmptyChoices() {
        let chunk = """
        {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[],"usage":{"prompt_tokens":120,\
        "completion_tokens":45,"total_tokens":165,"prompt_tokens_details":{"cached_tokens":100},\
        "completion_tokens_details":{"reasoning_tokens":30}}}
        """
        XCTAssertEqual(
            usage(chunk),
            TokenUsage(inputTokens: 120, outputTokens: 45, cachedInputTokens: 100, reasoningTokens: 30)
        )
    }

    func testOpenAIContentChunkWithNullUsageIsIgnored() {
        let chunk = """
        {"choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}],"usage":null}
        """
        XCTAssertNil(usage(chunk))
    }

    func testChunkWithoutUsageIsIgnored() {
        XCTAssertNil(usage(#"{"choices":[{"delta":{"content":"usage"}}]}"#))
    }

    func testResponsesAPICompletedEvent() {
        let event = """
        {"type":"response.completed","response":{"id":"resp_1","usage":{"input_tokens":300,\
        "input_tokens_details":{"cached_tokens":200},"output_tokens":80,\
        "output_tokens_details":{"reasoning_tokens":50},"total_tokens":380}}}
        """
        XCTAssertEqual(
            usage(event),
            TokenUsage(inputTokens: 300, outputTokens: 80, cachedInputTokens: 200, reasoningTokens: 50)
        )
    }

    func testAnthropicMessageStartAndDeltaMerge() throws {
        let start = """
        {"type":"message_start","message":{"id":"msg_1","role":"assistant","content":[],\
        "usage":{"input_tokens":25,"cache_read_input_tokens":1000,"cache_creation_input_tokens":0,"output_tokens":1}}}
        """
        let delta = """
        {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":512}}
        """
        let startUsage = try XCTUnwrap(usage(start))
        let deltaUsage = try XCTUnwrap(usage(delta))

        XCTAssertEqual(startUsage, TokenUsage(inputTokens: 1025, outputTokens: 1, cachedInputTokens: 1000))
        XCTAssertEqual(deltaUsage, TokenUsage(inputTokens: 0, outputTokens: 512))
        XCTAssertEqual(
            startUsage.merged(with: deltaUsage),
            TokenUsage(inputTokens: 1025, outputTokens: 512, cachedInputTokens: 1000)
        )
    }

    func testAnthropicNonStreamingBody() {
        let body = """
        {"id":"msg_1","type":"message","role":"assistant","content":[{"type":"text","text":"Hi"}],\
        "usage":{"input_tokens":10,"output_tokens":5}}
        """
        XCTAssertEqual(usage(body), TokenUsage(inputTokens: 10, outputTokens: 5))
    }

    func testOllamaDoneChunk() {
        let chunk = """
        {"model":"llama3.1","message":{"role":"assistant","content":""},"done":true,\
        "prompt_eval_count":26,"eval_count":290}
        """
        XCTAssertEqual(usage(chunk), TokenUsage(inputTokens: 26, outputTokens: 290))
    }

    func testOllamaIntermediateChunkHasNoUsage() {
        XCTAssertNil(usage(#"{"model":"llama3.1","message":{"role":"assistant","content":"Hi"},"done":false}"#))
    }

    func testGeminiUsageMetadataCountsThoughtsAsOutput() {
        let body = """
        {"candidates":[],"usageMetadata":{"promptTokenCount":40,"candidatesTokenCount":10,"thoughtsTokenCount":20}}
        """
        XCTAssertEqual(usage(body), TokenUsage(inputTokens: 40, outputTokens: 30, reasoningTokens: 20))
    }

    func testAddingSumsSeparateRequests() {
        let first = TokenUsage(inputTokens: 10, outputTokens: 5, cachedInputTokens: 2)
        let second = TokenUsage(inputTokens: 20, outputTokens: 7)
        XCTAssertEqual(first.adding(second), TokenUsage(inputTokens: 30, outputTokens: 12, cachedInputTokens: 2))
        XCTAssertEqual(first.adding(second).totalTokens, 42)
    }
}

final class UsageCostCalculatorTests: XCTestCase {
    func testKnownPricing() throws {
        let usage = TokenUsage(inputTokens: 1_000_000, outputTokens: 500_000, reasoningTokens: 200_000)
        let cost = UsageCostCalculator.cost(for: usage, providerType: "ChatGPT", modelId: "gpt-test") { provider, model in
            XCTAssertEqual(provider, "chatgpt")
            XCTAssertEqual(model, "gpt-test")
            return PricingInfo(inputPer1M: 2.0, outputPer1M: 8.0, source: "test")
        }
        // Reasoning tokens are part of output tokens and must not be billed twice.
        XCTAssertEqual(try XCTUnwrap(cost), 6.0, accuracy: 0.000001)
    }

    func testUnknownPricingReturnsNil() {
        let usage = TokenUsage(inputTokens: 10, outputTokens: 10)
        XCTAssertNil(UsageCostCalculator.cost(for: usage, providerType: "chatgpt", modelId: "x") { _, _ in nil })
    }

    func testMissingRateForUsedSideReturnsNil() {
        let usage = TokenUsage(inputTokens: 10, outputTokens: 10)
        let pricing = PricingInfo(inputPer1M: 1.0, outputPer1M: nil, source: "test")
        XCTAssertNil(UsageCostCalculator.cost(for: usage, pricing: pricing))
    }

    func testCachedInputBilledAtInputRate() throws {
        let usage = TokenUsage(inputTokens: 1_000, outputTokens: 0, cachedInputTokens: 800)
        let pricing = PricingInfo(inputPer1M: 3.0, outputPer1M: 15.0, source: "test")
        XCTAssertEqual(try XCTUnwrap(UsageCostCalculator.cost(for: usage, pricing: pricing)), 0.003, accuracy: 1e-9)
    }
}

final class MessageMetricsTests: XCTestCase {
    func testCodableRoundTripAndDerivedDurations() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let metrics = MessageMetrics(
            providerType: "claude",
            providerName: "Claude",
            modelId: "claude-sonnet",
            usage: TokenUsage(inputTokens: 100, outputTokens: 50, cachedInputTokens: 10, reasoningTokens: 5),
            costUSD: 0.0123,
            requestStart: start,
            firstTokenAt: start.addingTimeInterval(0.75),
            finishedAt: start.addingTimeInterval(4.5),
            reasoningStart: start.addingTimeInterval(0.75),
            reasoningEnd: start.addingTimeInterval(2.25)
        )

        let data = try MessageMetrics.jsonEncoder.encode(metrics)
        let decoded = try MessageMetrics.jsonDecoder.decode(MessageMetrics.self, from: data)

        XCTAssertEqual(decoded, metrics)
        XCTAssertEqual(try XCTUnwrap(decoded.timeToFirstToken), 0.75, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(decoded.totalDuration), 4.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(decoded.reasoningDuration), 1.5, accuracy: 0.001)
    }

    func testDurationsAreNilWithoutBothEndpoints() {
        let metrics = MessageMetrics(requestStart: Date())
        XCTAssertNil(metrics.timeToFirstToken)
        XCTAssertNil(metrics.totalDuration)
        XCTAssertNil(metrics.reasoningDuration)
    }
}
