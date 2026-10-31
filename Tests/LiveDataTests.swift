import XCTest
@testable import Tat

/// Hits the real Tencent / ESPN endpoints. Skipped unless `TAT_LIVE_TESTS=1`, so CI
/// never depends on third-party uptime. Run locally with:
/// `TEST_RUNNER_TAT_LIVE_TESTS=1 xcodebuild test -scheme TatUnit -only-testing:TatTests/LiveDataTests`
final class LiveDataTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TAT_LIVE_TESTS"] == "1", "set TAT_LIVE_TESTS=1 to run")
    }

    func testTencentReturnsEveryCatalogIndex() async throws {
        let codes = MarketIndex.catalog.map(\.code)
        let quotes = try await TencentMarketProvider().quotes(for: codes)
        XCTAssertEqual(quotes.map(\.code), codes)
        for quote in quotes {
            XCTAssertGreaterThan(quote.price, 0, quote.code)
            print("live quote:", quote.name, quote.price, quote.changePercent)
        }
    }

    func testESPNReturnsParsableScoreboards() async throws {
        let matches = try await ESPNMatchProvider().matches(
            leagues: League.catalog.map(\.path), on: Date(), calendar: .current
        )
        for match in matches {
            print("live match:", League.named(match.league), match.state, match.detail, match.home, match.homeScore ?? "-", match.awayScore ?? "-", match.away, match.kickoff)
        }
    }
}
