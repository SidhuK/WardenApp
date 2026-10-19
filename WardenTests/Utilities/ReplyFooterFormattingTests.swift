import XCTest
@testable import Warden

final class ReplyFooterFormattingTests: XCTestCase {
    func testTokenCounts() {
        XCTAssertEqual(ReplyFooterFormatting.tokens(1), "1 token")
        XCTAssertEqual(ReplyFooterFormatting.tokens(842), "842 tokens")
        XCTAssertEqual(ReplyFooterFormatting.tokens(1000), "1k tokens")
        XCTAssertEqual(ReplyFooterFormatting.tokens(1234), "1.2k tokens")
        XCTAssertEqual(ReplyFooterFormatting.tokens(9960), "10k tokens")
        XCTAssertEqual(ReplyFooterFormatting.tokens(12_345), "12k tokens")
        XCTAssertEqual(ReplyFooterFormatting.tokens(999_400), "999k tokens")
        XCTAssertEqual(ReplyFooterFormatting.tokens(999_600), "1M tokens")
        XCTAssertEqual(ReplyFooterFormatting.tokens(1_500_000), "1.5M tokens")
        XCTAssertEqual(ReplyFooterFormatting.tokenCount(-5), "0")
    }

    func testCost() {
        XCTAssertNil(ReplyFooterFormatting.cost(nil))
        XCTAssertNil(ReplyFooterFormatting.cost(.nan))
        XCTAssertEqual(ReplyFooterFormatting.cost(0), "$0.00")
        XCTAssertEqual(ReplyFooterFormatting.cost(0.00004), "<$0.0001")
        XCTAssertEqual(ReplyFooterFormatting.cost(0.0031), "$0.0031")
        XCTAssertEqual(ReplyFooterFormatting.cost(0.25), "$0.2500")
        XCTAssertEqual(ReplyFooterFormatting.cost(1.234), "$1.23")
    }

    func testDuration() {
        XCTAssertEqual(ReplyFooterFormatting.duration(0.01), "<0.1s")
        XCTAssertEqual(ReplyFooterFormatting.duration(4.21), "4.2s")
        XCTAssertEqual(ReplyFooterFormatting.duration(59.96), "1m 0s")
        XCTAssertEqual(ReplyFooterFormatting.duration(65.4), "1m 5s")
    }

    func testTokenBreakdown() {
        let usage = TokenUsage(inputTokens: 500, outputTokens: 300, cachedInputTokens: 200, reasoningTokens: 100)
        XCTAssertEqual(
            ReplyFooterFormatting.tokenBreakdown(usage),
            "Input: 500 tokens (200 cached)\nOutput: 300 tokens (100 reasoning)\nTotal: 800 tokens"
        )

        let plain = TokenUsage(inputTokens: 10, outputTokens: 5)
        XCTAssertEqual(
            ReplyFooterFormatting.tokenBreakdown(plain),
            "Input: 10 tokens\nOutput: 5 tokens\nTotal: 15 tokens"
        )
    }

    func testDurationBreakdown() {
        let start = Date(timeIntervalSince1970: 1000)
        let metrics = MessageMetrics(
            requestStart: start,
            firstTokenAt: start.addingTimeInterval(0.8),
            finishedAt: start.addingTimeInterval(4.2)
        )
        XCTAssertEqual(
            ReplyFooterFormatting.durationBreakdown(metrics),
            "Total: 4.2s\nTime to first token: 0.8s"
        )
        XCTAssertNil(ReplyFooterFormatting.durationBreakdown(MessageMetrics()))
    }

    func testChatRelativeTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2025, month: 6, day: 15, hour: 15))!

        func format(_ offset: TimeInterval) -> String {
            ChatRelativeTimeFormatting.shortString(from: now.addingTimeInterval(-offset), now: now, calendar: calendar)
        }

        XCTAssertEqual(format(10), "now")
        XCTAssertEqual(format(-30), "now")
        XCTAssertEqual(format(5 * 60), "5m")
        XCTAssertEqual(format(2 * 3600), "2h")
        XCTAssertEqual(format(20 * 3600), "Yesterday")
        XCTAssertEqual(format(3 * 86400), "3d")
        XCTAssertEqual(format(6 * 86400), "6d")
        XCTAssertNotEqual(format(10 * 86400), "10d")
    }
}
