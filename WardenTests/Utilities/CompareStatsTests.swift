import XCTest
@testable import Warden

final class CompareStatsTests: XCTestCase {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    private func candidate(
        _ id: UUID,
        success: Bool = true,
        duration: TimeInterval? = nil,
        cost: Double? = nil
    ) -> CompareCandidate {
        CompareCandidate(id: id, isSuccessful: success, totalDuration: duration, costUSD: cost)
    }

    func testPicksFastestAndCheapest() {
        let badges = CompareStats.badges(for: [
            candidate(a, duration: 2.0, cost: 0.01),
            candidate(b, duration: 1.0, cost: 0.02),
            candidate(c, duration: 3.0, cost: 0.005),
        ])
        XCTAssertEqual(badges[a], nil)
        XCTAssertEqual(badges[b], [.fastest])
        XCTAssertEqual(badges[c], [.cheapest])
    }

    func testOneColumnCanHaveBothBadges() {
        let badges = CompareStats.badges(for: [
            candidate(a, duration: 1.0, cost: 0.001),
            candidate(b, duration: 2.0, cost: 0.002),
        ])
        XCTAssertEqual(badges[a], [.fastest, .cheapest])
        XCTAssertNil(badges[b])
    }

    func testNoBadgesWithFewerThanTwoSuccessfulColumns() {
        let badges = CompareStats.badges(for: [
            candidate(a, duration: 1.0, cost: 0.001),
            candidate(b, success: false, duration: 0.5, cost: 0.0001),
        ])
        XCTAssertTrue(badges.isEmpty)
    }

    func testErroredColumnsAreExcluded() {
        let badges = CompareStats.badges(for: [
            candidate(a, success: false, duration: 0.1, cost: 0.0),
            candidate(b, duration: 2.0, cost: 0.02),
            candidate(c, duration: 3.0, cost: 0.01),
        ])
        XCTAssertNil(badges[a])
        XCTAssertEqual(badges[b], [.fastest])
        XCTAssertEqual(badges[c], [.cheapest])
    }

    func testNoCheapestWhenFewerThanTwoKnownCosts() {
        let badges = CompareStats.badges(for: [
            candidate(a, duration: 1.0, cost: 0.01),
            candidate(b, duration: 2.0, cost: nil),
            candidate(c, duration: 3.0, cost: nil),
        ])
        XCTAssertEqual(badges[a], [.fastest])
        XCTAssertNil(badges[b])
        XCTAssertNil(badges[c])
    }

    func testMissingDurationsAreSkipped() {
        let badges = CompareStats.badges(for: [
            candidate(a, duration: nil, cost: 0.01),
            candidate(b, duration: 2.0, cost: 0.02),
            candidate(c, duration: 3.0, cost: nil),
        ])
        XCTAssertEqual(badges[a], [.cheapest])
        XCTAssertEqual(badges[b], [.fastest])
        XCTAssertNil(badges[c])
    }

    func testTiesForBestAllGetBadge() {
        let badges = CompareStats.badges(for: [
            candidate(a, duration: 1.0, cost: 0.01),
            candidate(b, duration: 1.0, cost: 0.01),
            candidate(c, duration: 2.0, cost: 0.02),
        ])
        XCTAssertEqual(badges[a], [.fastest, .cheapest])
        XCTAssertEqual(badges[b], [.fastest, .cheapest])
        XCTAssertNil(badges[c])
    }

    func testNoBadgeWhenEveryoneTies() {
        let badges = CompareStats.badges(for: [
            candidate(a, duration: 1.0, cost: 0),
            candidate(b, duration: 2.0, cost: 0),
        ])
        XCTAssertEqual(badges[a], [.fastest])
        XCTAssertNil(badges[b])
    }

    func testFormatting() {
        XCTAssertEqual(CompareStats.formatDuration(0.84), "0.8s")
        XCTAssertEqual(CompareStats.formatDuration(4.2), "4.2s")
        XCTAssertEqual(CompareStats.formatDuration(65), "1m 05s")
        XCTAssertEqual(CompareStats.formatCost(0.0031), "$0.0031")
        XCTAssertEqual(CompareStats.formatCost(0.00001), "<$0.0001")
        XCTAssertEqual(CompareStats.formatCost(1.234), "$1.23")
        XCTAssertEqual(CompareStats.formatCost(0), "$0.00")
    }
}
