import XCTest
@testable import Tat

final class MarketParserTests: XCTestCase {
    func testParsesTencentSimpleQuotes() {
        let body = """
        v_s_sh000001="1~上证指数~000001~3599.02~-52.41~-1.44~497973940~76422719~~629591.07~ZS~";
        v_s_hkHSI="100~恒生指数~HSI~23294.420~335.770~1.46~21431781.9786~21431781.979~~0";
        v_s_usNDX="200~纳斯达克100~.NDX~28384.85~-1017.66~-3.46~2208196815~62679324764908~~";
        """
        let quotes = TencentMarketProvider.parse(body)
        XCTAssertEqual(quotes.map(\.code), ["sh000001", "hkHSI", "usNDX"])
        XCTAssertEqual(quotes[0], Quote(code: "sh000001", name: "上证指数", price: 3599.02, change: -52.41, changePercent: -1.44))
        XCTAssertEqual(quotes[1].changePercent, 1.46)
        XCTAssertEqual(quotes[2].name, "纳斯达克100")
    }

    func testSkipsUnknownAndMalformedLines() {
        let body = """
        v_pv_none_match="1";
        v_s_sh000001="1~上证指数~000001~--~~";
        v_s_usDJI="200~道琼斯~.DJI~51770.31~-572.25~-1.09~659029846~34198819328922~~";
        """
        XCTAssertEqual(TencentMarketProvider.parse(body).map(\.code), ["usDJI"])
    }

    func testDecodesGBK() throws {
        let gb18030 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        let data = try XCTUnwrap(#"v_s_sh000001="1~上证指数~000001~3599.02~-52.41~-1.44~";"#
            .data(using: String.Encoding(rawValue: gb18030)))
        let text = TencentMarketProvider.decodeGBK(data)
        XCTAssertTrue(text.contains("上证指数"))
        XCTAssertEqual(TencentMarketProvider.parse(text).first?.price, 3599.02)
    }
}

final class MatchParserTests: XCTestCase {
    private let fixture = """
    {"events":[
      {"id":"1","date":"2026-10-31T12:30Z",
       "status":{"type":{"state":"post","shortDetail":"FT"}},
       "competitions":[{"competitors":[
         {"homeAway":"home","score":"2","team":{"displayName":"Chelsea","shortDisplayName":"Chelsea","abbreviation":"CHE"}},
         {"homeAway":"away","score":"1","team":{"displayName":"Manchester United","shortDisplayName":"Man Utd","abbreviation":"MAN"}}]}]},
      {"id":"2","date":"2026-10-31T15:00Z",
       "status":{"type":{"state":"in","shortDetail":"67'"}},
       "competitions":[{"competitors":[
         {"homeAway":"away","score":"0","team":{"displayName":"Some New Club","shortDisplayName":"New Club"}},
         {"homeAway":"home","score":"3","team":{"displayName":"Manchester City","shortDisplayName":"Man City"}}]}]},
      {"id":"3","date":"2026-10-31T20:00:00Z",
       "status":{"type":{"state":"pre","shortDetail":"Scheduled"}},
       "competitions":[{"competitors":[
         {"homeAway":"home","score":"0","team":{"displayName":"Aston Villa"}},
         {"homeAway":"away","score":"0","team":{"displayName":"Fulham"}}]}]},
      {"id":"broken","date":"not a date","competitions":[]}
    ]}
    """

    func testParsesScoreboard() throws {
        let matches = try ESPNMatchProvider.parse(Data(fixture.utf8), league: "soccer/eng.1")
        XCTAssertEqual(matches.map(\.id), ["1", "2", "3"])

        XCTAssertEqual(matches[0].state, .finished)
        XCTAssertEqual(matches[0].home, "切尔西")
        XCTAssertEqual(matches[0].away, "曼联")
        XCTAssertEqual(matches[0].homeScore, "2")
        XCTAssertEqual(matches[0].kickoff, ISO8601DateFormatter().date(from: "2026-10-31T12:30:00Z"))

        XCTAssertEqual(matches[1].state, .live)
        XCTAssertEqual(matches[1].detail, "67'")
        XCTAssertEqual(matches[1].home, "曼城", "home/away come from homeAway, not array order")
        XCTAssertEqual(matches[1].away, "New Club", "unknown clubs fall back to the English short name")

        XCTAssertEqual(matches[2].state, .scheduled)
        XCTAssertNil(matches[2].homeScore, "no score before kickoff")
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try ESPNMatchProvider.parse(Data("<html>".utf8), league: "x"))
    }

    func testTodayWindowRunsUntilSixTheNextMorning() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let noon = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12)))
        let window = MatchWindow.interval(for: noon, calendar: calendar)

        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 31)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 6)))
        XCTAssertEqual(window.start, start)
        XCTAssertEqual(window.end, end)

        // A 20:00 UTC kickoff is 04:00 next day in Beijing: still "tonight".
        XCTAssertTrue(window.contains(try XCTUnwrap(ESPNMatchProvider.parseDate("2026-10-31T20:00Z"))))
        // 16:30 UTC on Nov 1 is 00:30 Nov 2 in Beijing: not today.
        XCTAssertFalse(window.contains(try XCTUnwrap(ESPNMatchProvider.parseDate("2026-11-01T16:30Z"))))
    }
}

@MainActor
final class TipsStoreTests: XCTestCase {
    private struct FailingMarket: MarketProviding {
        func quotes(for codes: [String]) async throws -> [Quote] { throw TipsError.badResponse }
    }

    private func settings() -> AppSettings {
        let suite = "tat.tests.\(UUID().uuidString)"
        return AppSettings(defaults: UserDefaults(suiteName: suite)!)
    }

    private func waitUntilLoaded(_ store: TipsStore) async {
        for _ in 0..<200 where store.isLoading {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testRefreshLoadsBothSections() async {
        let store = TipsStore(settings: settings(), marketProvider: StubMarketProvider(), matchProvider: StubMatchProvider())
        XCTAssertTrue(store.isStale)
        store.refresh()
        XCTAssertTrue(store.isLoading)
        await waitUntilLoaded(store)

        guard case .loaded(let quotes) = store.markets else { return XCTFail("markets not loaded: \(store.markets)") }
        XCTAssertEqual(quotes.map(\.code), MarketIndex.defaultCodes)
        guard case .loaded(let matches) = store.matches else { return XCTFail("matches not loaded") }
        XCTAssertEqual(matches.count, 3)
        XCTAssertFalse(store.isStale)
    }

    func testOneFailingSectionDoesNotBreakTheOther() async {
        let store = TipsStore(settings: settings(), marketProvider: FailingMarket(), matchProvider: StubMatchProvider())
        store.refresh()
        await waitUntilLoaded(store)
        XCTAssertEqual(store.markets, .failed("服务暂时不可用"))
        guard case .loaded = store.matches else { return XCTFail("matches should still load") }
    }

    func testStaleAfterThreeMinutes() async {
        var now = Date(timeIntervalSince1970: 0)
        let store = TipsStore(settings: settings(), marketProvider: StubMarketProvider(), matchProvider: StubMatchProvider(), now: { now })
        store.refresh()
        await waitUntilLoaded(store)
        now = now.addingTimeInterval(TipsStore.staleAfter - 1)
        XCTAssertFalse(store.isStale)
        now = now.addingTimeInterval(2)
        XCTAssertTrue(store.isStale)
    }
}

@MainActor
final class AppSettingsTests: XCTestCase {
    func testDefaultsAndCatalogOrder() {
        let defaults = UserDefaults(suiteName: "tat.tests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.isPinned)
        XCTAssertEqual(settings.triggerDelay, .short)
        XCTAssertTrue(settings.redMeansUp)
        XCTAssertEqual(settings.enabledLeagues, ["soccer/eng.1"])

        settings.setIndex("usNDX", enabled: false)
        settings.setIndex("sh000300", enabled: true)
        XCTAssertEqual(settings.enabledIndices, ["sh000001", "sz399001", "sz399006", "sh000300", "hkHSI", "usINX", "usDJI"])

        settings.setLeague("basketball/nba", enabled: true)
        settings.isPinned = true
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.enabledLeagues, ["soccer/eng.1", "basketball/nba"])
        XCTAssertTrue(reloaded.isPinned)
    }
}
