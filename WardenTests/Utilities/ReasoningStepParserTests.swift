import XCTest
@testable import Warden

final class ReasoningStepParserTests: XCTestCase {
    func testBoldHeadingsStartSteps() {
        let text = """
            **Understanding the question**
            The user wants a sorted list.

            **Choosing an algorithm**
            Merge sort is stable.
            It runs in n log n.
            """
        XCTAssertEqual(
            ReasoningStepParser.parse(text),
            [
                ReasoningStep(title: "Understanding the question", body: "The user wants a sorted list."),
                ReasoningStep(title: "Choosing an algorithm", body: "Merge sort is stable.\nIt runs in n log n."),
            ]
        )
    }

    func testMarkdownHeadingsStartSteps() {
        let text = """
            # First
            Alpha.
            ## Second ##
            Beta.
            ### Third
            Gamma.
            """
        XCTAssertEqual(
            ReasoningStepParser.parse(text),
            [
                ReasoningStep(title: "First", body: "Alpha."),
                ReasoningStep(title: "Second", body: "Beta."),
                ReasoningStep(title: "Third", body: "Gamma."),
            ]
        )
    }

    func testDeepMarkdownHeadingAndHashtagAreNotHeadings() {
        XCTAssertNil(ReasoningStepParser.headingTitle("#### Too deep"))
        XCTAssertNil(ReasoningStepParser.headingTitle("#hashtag"))
    }

    func testClosingHashesNeedLeadingWhitespace() {
        XCTAssertEqual(ReasoningStepParser.headingTitle("## Implement in C#"), "Implement in C#")
        XCTAssertEqual(ReasoningStepParser.headingTitle("## Plan ##"), "Plan")
        XCTAssertEqual(ReasoningStepParser.headingTitle("### F# and C# ###"), "F# and C#")
    }

    func testIndentedHeadingIsCode() {
        XCTAssertEqual(ReasoningStepParser.headingTitle("   ## Three spaces"), "Three spaces")
        XCTAssertNil(ReasoningStepParser.headingTitle("    ## Four spaces"))
        XCTAssertNil(ReasoningStepParser.headingTitle("\t## Tab"))
        XCTAssertNil(ReasoningStepParser.headingTitle("    **Bold**"))
    }

    func testHeadingsWithTrailingColon() {
        XCTAssertEqual(ReasoningStepParser.headingTitle("**Plan:**"), "Plan")
        XCTAssertEqual(ReasoningStepParser.headingTitle("**Plan**:"), "Plan")
        XCTAssertEqual(ReasoningStepParser.headingTitle("  ## Next steps:  "), "Next steps")
    }

    func testBoldInsideSentenceIsNotHeading() {
        XCTAssertNil(ReasoningStepParser.headingTitle("This is **important** to note."))
        XCTAssertNil(ReasoningStepParser.headingTitle("**Note:** the list is empty."))
        XCTAssertNil(ReasoningStepParser.headingTitle("**a** and **b**"))
        XCTAssertNil(ReasoningStepParser.headingTitle("****"))

        let text = "I think **this** matters.\nAnd so does that."
        XCTAssertEqual(ReasoningStepParser.parse(text), [ReasoningStep(title: nil, body: text)])
    }

    func testTextBeforeFirstHeadingBecomesUntitledStep() {
        let text = "Preamble here.\n\n**Step**\nDetails."
        XCTAssertEqual(
            ReasoningStepParser.parse(text),
            [
                ReasoningStep(title: nil, body: "Preamble here."),
                ReasoningStep(title: "Step", body: "Details."),
            ]
        )
    }

    func testHeadingInsideCodeFenceIsIgnored() {
        let text = "Look at this:\n```\n# comment\nx = 1\n```"
        XCTAssertEqual(ReasoningStepParser.parse(text), [ReasoningStep(title: nil, body: text)])
    }

    func testParagraphsWithoutHeadingsGetDerivedTitles() {
        let text = """
            Let me think about the input. It has three parts.

            Next I check **edge cases** like empty arrays.
            """
        XCTAssertEqual(
            ReasoningStepParser.parse(text),
            [
                ReasoningStep(
                    title: "Let me think about the input",
                    body: "Let me think about the input. It has three parts."
                ),
                ReasoningStep(
                    title: "Next I check edge cases like empty arrays",
                    body: "Next I check **edge cases** like empty arrays."
                ),
            ]
        )
    }

    func testLongDerivedTitleIsTruncated() throws {
        let sentence =
            "This is a deliberately long first sentence that keeps going well past the sixty character limit."
        let steps = ReasoningStepParser.parse("\(sentence)\n\nSecond paragraph.")
        XCTAssertEqual(steps.count, 2)
        let title = try XCTUnwrap(steps[0].title)
        XCTAssertLessThanOrEqual(title.count, ReasoningStepParser.maxDerivedTitleLength)
        XCTAssertEqual(title, "This is a deliberately long first sentence that keeps going…")
        XCTAssertEqual(steps[0].body, sentence)
    }

    func testTruncationBacksUpToWordBoundary() throws {
        let sentence = "Considering the implications of extraordinarily complex multidimensional data"
        let steps = ReasoningStepParser.parse("\(sentence)\n\nMore.")
        let title = try XCTUnwrap(steps.first?.title)
        XCTAssertEqual(title, "Considering the implications of extraordinarily complex…")
    }

    func testSingleParagraphHasNoTitle() {
        let text = "  Just one paragraph.\nSpanning two lines.  \n"
        XCTAssertEqual(
            ReasoningStepParser.parse(text),
            [ReasoningStep(title: nil, body: "Just one paragraph.\nSpanning two lines.")]
        )
    }

    func testEmptyAndWhitespaceReturnNoSteps() {
        XCTAssertEqual(ReasoningStepParser.parse(""), [])
        XCTAssertEqual(ReasoningStepParser.parse("  \n\t\r\n "), [])
    }

    func testCRLFLineEndings() {
        let headings = ReasoningStepParser.parse("**One**\r\nA.\r\n\r\n**Two**\r\nB.")
        XCTAssertEqual(
            headings,
            [ReasoningStep(title: "One", body: "A."), ReasoningStep(title: "Two", body: "B.")]
        )

        let paragraphs = ReasoningStepParser.parse("First idea.\r\n\r\nSecond idea.")
        XCTAssertEqual(
            paragraphs,
            [
                ReasoningStep(title: "First idea", body: "First idea."),
                ReasoningStep(title: "Second idea", body: "Second idea."),
            ]
        )
    }

    func testHeadingWithEmptyBodyIsKept() {
        XCTAssertEqual(
            ReasoningStepParser.parse("**Done**"),
            [ReasoningStep(title: "Done", body: "")]
        )
    }
}
