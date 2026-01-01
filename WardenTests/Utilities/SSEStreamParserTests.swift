import XCTest
@testable import Warden

final class SSEStreamParserTests: XCTestCase {
    func testBufferedWithCompatibilityFlushFlushesOnCompleteJSONWithoutBlankLine() async throws {
        let data = "data: {\"a\":1}\n".data(using: .utf8)!
        var events: [String] = []

        try await SSEStreamParser.parse(data: data, deliveryMode: .bufferedWithCompatibilityFlush) { payload in
            events.append(payload)
        }

        XCTAssertEqual(events, ["{\"a\":1}"])
    }

    func testBufferedWithCompatibilityFlushFlushesOnFinalUnterminatedLine() async throws {
        let data = "data: {\"a\":1}".data(using: .utf8)!
        var events: [String] = []

        try await SSEStreamParser.parse(data: data, deliveryMode: .bufferedWithCompatibilityFlush) { payload in
            events.append(payload)
        }

        XCTAssertEqual(events, ["{\"a\":1}"])
    }

    func testIgnoresCommentsAndNonDataFields() async throws {
        let data = """
        : keepalive
        event: message
        data: hello

        """.data(using: .utf8)!
        var events: [String] = []

        try await SSEStreamParser.parse(data: data, deliveryMode: .bufferedEvents) { payload in
            events.append(payload)
        }

        XCTAssertEqual(events, ["hello"])
    }
}

