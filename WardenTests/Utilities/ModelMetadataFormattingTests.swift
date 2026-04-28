import XCTest
@testable import Warden

final class ModelMetadataFormattingTests: XCTestCase {
    func testClaudePointReleaseSuffixIsPreserved() {
        let displayName = ModelMetadata.formatModelDisplayName(modelId: "claude-sonnet-4-5")

        XCTAssertEqual(displayName, "Claude Sonnet 4.5")
    }

    func testClaudeDateSuffixIsPreserved() {
        let displayName = ModelMetadata.formatModelDisplayName(modelId: "claude-3-5-sonnet-20241022")

        XCTAssertEqual(displayName, "Claude 3.5 Sonnet (20241022)")
    }

    func testNonClaudeKnownModelSuffixIsPreserved() {
        let displayName = ModelMetadata.formatModelDisplayName(modelId: "gpt-4o-mini-2024-07-18")

        XCTAssertEqual(displayName, "GPT-4o Mini (2024-07-18)")
    }

    func testClaudePointReleaseAndDateSuffixIsPreserved() {
        let displayName = ModelMetadata.formatModelDisplayName(modelId: "claude-opus-4-5-20251101")

        XCTAssertEqual(displayName, "Claude Opus 4.5 (20251101)")
    }

    func testClaudeMinorReleaseAndDateSuffixIsPreserved() {
        let displayName = ModelMetadata.formatModelDisplayName(modelId: "claude-opus-4-1-20250805")

        XCTAssertEqual(displayName, "Claude Opus 4.1 (20250805)")
    }

    func testClaudeHaikuPointReleaseAndDateSuffixIsPreserved() {
        let displayName = ModelMetadata.formatModelDisplayName(modelId: "claude-haiku-4-5-20251001")

        XCTAssertEqual(displayName, "Claude Haiku 4.5 (20251001)")
    }
}

final class QuickChatClipboardContextTests: XCTestCase {
    func testClipboardContextUsesTextWhenEnabled() {
        let context = QuickChatView.clipboardContext(from: "Existing clipboard text", usesClipboardContext: true)

        XCTAssertEqual(context, "Existing clipboard text")
    }

    func testClipboardContextIgnoresTextWhenDisabled() {
        let context = QuickChatView.clipboardContext(from: "Existing clipboard text", usesClipboardContext: false)

        XCTAssertNil(context)
    }
}
