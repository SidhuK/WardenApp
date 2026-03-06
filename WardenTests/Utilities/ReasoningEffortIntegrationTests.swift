import XCTest
@testable import Warden

final class ReasoningEffortIntegrationTests: XCTestCase {
    func testChatGPTHandlerIncludesReasoningEffortForReasoningModels() throws {
        let config = APIServiceConfig(
            name: "chatgpt",
            apiUrl: URL(string: "https://example.com/v1/chat/completions")!,
            apiKey: "test",
            model: "o1"
        )

        let handler = ChatGPTHandler(config: config, session: .shared, streamingSession: .shared)
        let request = try handler.prepareRequest(
            requestMessages: [["role": "user", "content": "hi"]],
            tools: nil,
            model: config.model,
            settings: GenerationSettings(temperature: 0.2, reasoningEffort: .extraHigh),
            stream: false
        )

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["reasoning_effort"] as? String, "xhigh")
    }

    func testOpenRouterHandlerIncludesIncludeReasoningAndReasoningEffortWhenEnabled() throws {
        let config = APIServiceConfig(
            name: "openrouter",
            apiUrl: URL(string: "https://example.com/api/v1/chat/completions")!,
            apiKey: "test",
            model: "openai/o1"
        )

        let handler = OpenRouterHandler(config: config, session: .shared, streamingSession: .shared)
        let request = try handler.prepareRequest(
            requestMessages: [["role": "user", "content": "hi"]],
            tools: nil,
            model: config.model,
            settings: GenerationSettings(temperature: 0.2, reasoningEffort: .low),
            stream: false
        )

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["reasoning_effort"] as? String, "low")
        XCTAssertEqual(json["include_reasoning"] as? Bool, true)
    }

    func testClaudeHandlerAddsThinkingConfigWhenEnabled() throws {
        let config = APIServiceConfig(
            name: "claude",
            apiUrl: URL(string: "https://example.com/v1/messages")!,
            apiKey: "test",
            model: "claude-3-5-sonnet-latest"
        )

        let handler = ClaudeHandler(config: config, session: .shared, streamingSession: .shared)
        let request = try handler.prepareRequest(
            requestMessages: [["role": "user", "content": "hi"]],
            tools: nil,
            model: config.model,
            settings: GenerationSettings(temperature: 0.2, reasoningEffort: .high),
            stream: false
        )

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let thinking = try XCTUnwrap(json["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["type"] as? String, "enabled")
        XCTAssertNotNil(thinking["budget_tokens"] as? Int)
    }

    func testClaudeStreamingThinkingDeltaIsEmittedAsReasoningRole() throws {
        let config = APIServiceConfig(
            name: "claude",
            apiUrl: URL(string: "https://example.com/v1/messages")!,
            apiKey: "test",
            model: "claude-3-5-sonnet-latest"
        )
        let handler = ClaudeHandler(config: config, session: .shared, streamingSession: .shared)

        let event = """
        {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"foo"}}
        """
        let (finished, error, messageData, role, _) = handler.parseDeltaJSONResponse(data: event.data(using: .utf8))
        XCTAssertFalse(finished)
        XCTAssertNil(error)
        XCTAssertEqual(messageData, "foo")
        XCTAssertEqual(role, "reasoning")
    }

    func testGeminiHandlerOmitsReasoningEffortWhenOff() async throws {
        let config = APIServiceConfig(
            name: "gemini",
            apiUrl: URL(string: "https://example.com/v1beta/chat/completions")!,
            apiKey: "test",
            model: "gemini-thinking-model"
        )

        let existingMetadata = ModelMetadataStorage.getMetadata(provider: "gemini", modelId: config.model)
        defer {
            if let existingMetadata {
                ModelMetadataStorage.store(metadata: existingMetadata, provider: "gemini")
            } else {
                ModelMetadataStorage.removeMetadata(provider: "gemini", modelId: config.model)
            }
        }

        let metadata = ModelMetadata(
            modelId: config.model,
            provider: "gemini",
            pricing: nil,
            maxContextTokens: nil,
            capabilities: ["reasoning"],
            latency: nil,
            costLevel: nil,
            lastUpdated: Date(),
            source: .unknown
        )
        ModelMetadataStorage.store(metadata: metadata, provider: "gemini")

        let handler = GeminiHandler(config: config, session: .shared, streamingSession: .shared)
        let request = try await handler.prepareRequest(
            requestMessages: [["role": "user", "content": "hi"]],
            tools: nil,
            model: config.model,
            settings: GenerationSettings(temperature: 0.2, reasoningEffort: .off),
            attachmentPolicy: .preferProviderAttachments,
            stream: false
        )

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(json["reasoning_effort"])
    }

    func testGeminiHandlerKeepsReasoningEffortWhenEnabled() async throws {
        let config = APIServiceConfig(
            name: "gemini",
            apiUrl: URL(string: "https://example.com/v1beta/chat/completions")!,
            apiKey: "test",
            model: "gemini-thinking-model"
        )

        let existingMetadata = ModelMetadataStorage.getMetadata(provider: "gemini", modelId: config.model)
        defer {
            if let existingMetadata {
                ModelMetadataStorage.store(metadata: existingMetadata, provider: "gemini")
            } else {
                ModelMetadataStorage.removeMetadata(provider: "gemini", modelId: config.model)
            }
        }

        let metadata = ModelMetadata(
            modelId: config.model,
            provider: "gemini",
            pricing: nil,
            maxContextTokens: nil,
            capabilities: ["reasoning"],
            latency: nil,
            costLevel: nil,
            lastUpdated: Date(),
            source: .unknown
        )
        ModelMetadataStorage.store(metadata: metadata, provider: "gemini")

        let handler = GeminiHandler(config: config, session: .shared, streamingSession: .shared)
        let request = try await handler.prepareRequest(
            requestMessages: [["role": "user", "content": "hi"]],
            tools: nil,
            model: config.model,
            settings: GenerationSettings(temperature: 0.2, reasoningEffort: .medium),
            attachmentPolicy: .preferProviderAttachments,
            stream: false
        )

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["reasoning_effort"] as? String, "medium")
    }

    func testReasoningCompatibilityDetectsUnsupportedParameter() {
        let error = APIError.serverError("Client Error: {\"error\":\"Unknown parameter: reasoning_effort\"}")
        let settings = GenerationSettings(temperature: 0.2, reasoningEffort: .low)
        XCTAssertTrue(ReasoningCompatibility.shouldRetryWithoutReasoning(settings: settings, error: error))
    }
}
