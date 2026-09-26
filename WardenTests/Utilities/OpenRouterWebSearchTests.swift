import XCTest
@testable import Warden

final class OpenRouterWebSearchTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: AppConstants.preferProviderWebSearchKey)
        UserDefaults.standard.removeObject(forKey: AppConstants.webSearchMaxResultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppConstants.preferProviderWebSearchKey)
        UserDefaults.standard.removeObject(forKey: AppConstants.webSearchMaxResultsKey)
        super.tearDown()
    }

    private func makeHandler(model: String = "openai/gpt-4o") -> (handler: OpenRouterHandler, model: String) {
        let config = APIServiceConfig(
            name: "openrouter",
            apiUrl: URL(string: "https://example.com/api/v1/chat/completions")!,
            apiKey: "test",
            model: model
        )
        let handler = OpenRouterHandler(config: config, session: .shared, streamingSession: .shared)
        return (handler, config.model)
    }

    private func bodyJSON(of request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func annotationChunk(url: String, title: String) -> Data {
        let payload: [String: Any] = [
            "choices": [
                [
                    "delta": [
                        "annotations": [
                            [
                                "type": "url_citation",
                                "url_citation": ["url": url, "title": title],
                            ]
                        ]
                    ]
                ]
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    // MARK: - Request building

    func testPrepareRequestAddsWebPluginWhenServerWebSearchEnabled() async throws {
        let (handler, model) = makeHandler()
        let request = try await handler.prepareRequest(
            requestMessages: [["role": "user", "content": "hi"]],
            tools: nil,
            model: model,
            settings: GenerationSettings(temperature: 0.2, serverWebSearch: true, webSearchMaxResults: 3),
            attachmentPolicy: .preferProviderAttachments,
            stream: false
        )

        let json = try bodyJSON(of: request)
        let plugins = try XCTUnwrap(json["plugins"] as? [[String: Any]])
        XCTAssertEqual(plugins.count, 1)
        XCTAssertEqual(plugins.first?["id"] as? String, "web")
        XCTAssertEqual(plugins.first?["max_results"] as? Int, 3)
    }

    func testPrepareRequestOmitsWebPluginByDefault() async throws {
        let (handler, model) = makeHandler()
        let request = try await handler.prepareRequest(
            requestMessages: [["role": "user", "content": "hi"]],
            tools: nil,
            model: model,
            settings: GenerationSettings(temperature: 0.2),
            attachmentPolicy: .preferProviderAttachments,
            stream: false
        )

        let json = try bodyJSON(of: request)
        XCTAssertNil(json["plugins"])
    }

    func testPrepareRequestUsesStoredMaxResultsPreferenceAsFallback() async throws {
        UserDefaults.standard.set(7, forKey: AppConstants.webSearchMaxResultsKey)

        let (handler, model) = makeHandler()
        let request = try await handler.prepareRequest(
            requestMessages: [["role": "user", "content": "hi"]],
            tools: nil,
            model: model,
            settings: GenerationSettings(temperature: 0.2, serverWebSearch: true),
            attachmentPolicy: .preferProviderAttachments,
            stream: false
        )

        let json = try bodyJSON(of: request)
        let plugins = try XCTUnwrap(json["plugins"] as? [[String: Any]])
        XCTAssertEqual(plugins.first?["max_results"] as? Int, 7)
    }

    // MARK: - Annotation parsing

    func testParseJSONResponseReportsAnnotationSources() throws {
        let (handler, _) = makeHandler()
        var reportedSources: [SearchSource]?
        handler.onWebSearchSources = { reportedSources = $0 }

        let payload: [String: Any] = [
            "choices": [
                [
                    "message": [
                        "role": "assistant",
                        "content": "Here is what I found.",
                        "annotations": [
                            [
                                "type": "url_citation",
                                "url_citation": [
                                    "url": "https://example.com/a",
                                    "title": "Example A",
                                    "content": "Relevant excerpt.",
                                    "start_index": 0,
                                    "end_index": 10,
                                ],
                            ]
                        ],
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        let (content, role, _) = try XCTUnwrap(handler.parseJSONResponse(data: data))

        XCTAssertEqual(content, "Here is what I found.")
        XCTAssertEqual(role, "assistant")
        let sources = try XCTUnwrap(reportedSources)
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.url, "https://example.com/a")
        XCTAssertEqual(sources.first?.title, "Example A")
    }

    func testParseDeltaJSONResponseAccumulatesAndDeduplicatesSources() throws {
        let (handler, _) = makeHandler()
        var updates: [[SearchSource]] = []
        handler.onWebSearchSources = { updates.append($0) }

        _ = handler.parseDeltaJSONResponse(data: annotationChunk(url: "https://example.com/a", title: "A"))
        _ = handler.parseDeltaJSONResponse(data: annotationChunk(url: "https://example.com/a", title: "A"))
        _ = handler.parseDeltaJSONResponse(data: annotationChunk(url: "https://example.com/b", title: "B"))

        XCTAssertEqual(updates.count, 3)
        let finalSources = try XCTUnwrap(updates.last)
        XCTAssertEqual(finalSources.count, 2)
        XCTAssertEqual(
            finalSources.map { $0.url },
            ["https://example.com/a", "https://example.com/b"],
            "sources must keep citation order"
        )
    }

    func testParseDeltaJSONResponseWithoutAnnotationsDoesNotReportSources() {
        let (handler, _) = makeHandler()
        var reportedSources: [SearchSource]?
        handler.onWebSearchSources = { reportedSources = $0 }

        let payload: [String: Any] = [
            "choices": [["delta": ["content": "plain answer"]]]
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)

        _ = handler.parseDeltaJSONResponse(data: data)

        XCTAssertNil(reportedSources)
    }

    func testAnnotationParsingIgnoresMalformedCitations() {
        let (handler, _) = makeHandler()
        var reportedSources: [SearchSource]?
        handler.onWebSearchSources = { reportedSources = $0 }

        let payload: [String: Any] = [
            "choices": [
                [
                    "delta": [
                        "annotations": [
                            ["type": "url_citation"],
                            ["type": "url_citation", "url_citation": ["title": "No URL"]],
                        ]
                    ]
                ]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)

        _ = handler.parseDeltaJSONResponse(data: data)

        XCTAssertNil(reportedSources)
    }

    // MARK: - Provider-side search preference routing

    private func withPreference(_ value: Bool?, _ body: () -> Void) {
        if let value {
            UserDefaults.standard.set(value, forKey: AppConstants.preferProviderWebSearchKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppConstants.preferProviderWebSearchKey)
        }
        body()
    }

    func testProviderSearchPreferenceDefaultsToEnabledForOpenRouter() {
        withPreference(nil) {
            XCTAssertTrue(ServerWebSearch.preferred(providerName: "openrouter"))
            XCTAssertTrue(ServerWebSearch.preferred(providerName: "OpenRouter"))
            XCTAssertTrue(ServerWebSearch.preferred(providerName: "Open Router"))
        }
    }

    func testProviderSearchPreferenceNeverAppliesToOtherProviders() {
        withPreference(nil) {
            XCTAssertFalse(ServerWebSearch.preferred(providerName: "chatgpt"))
            XCTAssertFalse(ServerWebSearch.preferred(providerName: "claude"))
        }
        withPreference(true) {
            XCTAssertFalse(ServerWebSearch.preferred(providerName: "chatgpt"))
        }
    }

    func testDisablingProviderSearchPreferenceFallsBackToExternalProviders() {
        withPreference(false) {
            XCTAssertFalse(ServerWebSearch.preferred(providerName: "openrouter"))
        }
    }

    func testExplicitlyEnabledProviderSearchPreferenceStaysEnabled() {
        withPreference(true) {
            XCTAssertTrue(ServerWebSearch.preferred(providerName: "openrouter"))
        }
    }
}
