import Foundation

/// Deterministic data for UI tests (`-uiTesting`), so end-to-end runs never depend on the network.
struct StubMarketProvider: MarketProviding {
    func quotes(for codes: [String]) async throws -> [Quote] {
        let sample: [String: (Double, Double, Double)] = [
            "sh000001": (3599.02, -52.41, -1.44),
            "sz399001": (10833.78, -304.42, -2.73),
            "sz399006": (2413.63, -103.96, -4.13),
            "hkHSI": (23294.42, 335.77, 1.46),
            "usNDX": (28384.85, -1017.66, -3.46),
            "usINX": (7580.07, -140.32, -1.82),
            "usDJI": (51770.31, -572.25, -1.09),
        ]
        return codes.map { code in
            let (price, change, percent) = sample[code] ?? (1000, 10, 1)
            return Quote(code: code, name: MarketIndex.named(code), price: price, change: change, changePercent: percent)
        }
    }
}

struct StubMatchProvider: MatchProviding {
    func matches(leagues: [String], on day: Date, calendar: Calendar) async throws -> [Match] {
        let start = calendar.startOfDay(for: day)
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: start) ?? start
        }
        return leagues.flatMap { league -> [Match] in
            guard league == "soccer/eng.1" else { return [] }
            return [
                Match(id: "1", league: league, kickoff: at(20, 30), state: .finished, detail: "FT",
                      home: "切尔西", away: "曼联", homeScore: "2", awayScore: "1"),
                Match(id: "2", league: league, kickoff: at(23), state: .live, detail: "67'",
                      home: "曼城", away: "布莱顿", homeScore: "1", awayScore: "1"),
                Match(id: "3", league: league, kickoff: at(28), state: .scheduled, detail: "",
                      home: "阿斯顿维拉", away: "富勒姆", homeScore: nil, awayScore: nil),
            ]
        }
    }
}
