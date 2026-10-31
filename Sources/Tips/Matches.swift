import Foundation

struct League: Identifiable, Hashable, Sendable {
    /// ESPN sport/league path, e.g. `soccer/eng.1`.
    let path: String
    let name: String

    var id: String { path }

    static let catalog: [League] = [
        League(path: "soccer/eng.1", name: "英超"),
        League(path: "soccer/esp.1", name: "西甲"),
        League(path: "soccer/ita.1", name: "意甲"),
        League(path: "soccer/ger.1", name: "德甲"),
        League(path: "soccer/fra.1", name: "法甲"),
        League(path: "soccer/uefa.champions", name: "欧冠"),
        League(path: "soccer/chn.1", name: "中超"),
        League(path: "basketball/nba", name: "NBA"),
    ]

    static let defaultPaths = ["soccer/eng.1"]

    static func named(_ path: String) -> String {
        catalog.first { $0.path == path }?.name ?? path
    }
}

struct Match: Identifiable, Equatable, Sendable {
    enum State: String, Sendable {
        case scheduled, live, finished
    }

    let id: String
    let league: String
    let kickoff: Date
    let state: State
    /// ESPN's short status, e.g. `67'`, `HT`, `FT`.
    let detail: String
    let home: String
    let away: String
    let homeScore: String?
    let awayScore: String?
}

protocol MatchProviding: Sendable {
    func matches(leagues: [String], on day: Date, calendar: Calendar) async throws -> [Match]
}

/// "Today" for a sports fan in the evening: local 00:00 until 06:00 the next morning,
/// so late-night kickoffs (common for Europe viewed from Asia) still count as tonight.
enum MatchWindow {
    static let overnightHours = 30

    static func interval(for day: Date, calendar: Calendar) -> DateInterval {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .hour, value: overnightHours, to: start) ?? start.addingTimeInterval(30 * 3600)
        return DateInterval(start: start, end: end)
    }
}

/// Fixtures from ESPN's public scoreboard endpoint (no API key).
/// ESPN buckets events by US date, so we fetch yesterday/today/tomorrow and filter locally.
struct ESPNMatchProvider: MatchProviding {
    var session: URLSession = .shared

    func matches(leagues: [String], on day: Date, calendar: Calendar) async throws -> [Match] {
        guard !leagues.isEmpty else { return [] }
        let window = MatchWindow.interval(for: day, calendar: calendar)
        let dates = (-1...1).compactMap { calendar.date(byAdding: .day, value: $0, to: day) }

        let all = try await withThrowingTaskGroup(of: [Match].self) { group in
            for league in leagues {
                for date in dates {
                    group.addTask { try await fetch(league: league, date: date, calendar: calendar) }
                }
            }
            var result: [Match] = []
            for try await batch in group { result += batch }
            return result
        }

        var seen = Set<String>()
        return all
            .filter { window.contains($0.kickoff) && seen.insert($0.id).inserted }
            .sorted { ($0.kickoff, $0.id) < ($1.kickoff, $1.id) }
    }

    private func fetch(league: String, date: Date, calendar: Calendar) async throws -> [Match] {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let stamp = String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(league)/scoreboard?dates=\(stamp)") else {
            throw TipsError.badResponse
        }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw TipsError.badResponse }
        return try Self.parse(data, league: league)
    }

    static func parse(_ data: Data, league: String) throws -> [Match] {
        let board: Scoreboard
        do {
            board = try JSONDecoder().decode(Scoreboard.self, from: data)
        } catch {
            throw TipsError.undecodable
        }
        return board.events.compactMap { event -> Match? in
            guard let kickoff = parseDate(event.date),
                  let competition = event.competitions.first,
                  let home = competition.competitors.first(where: { $0.homeAway == "home" }),
                  let away = competition.competitors.first(where: { $0.homeAway == "away" })
            else { return nil }
            let status = event.status?.type ?? competition.status?.type
            let state: Match.State = switch status?.state {
            case "in": .live
            case "post": .finished
            default: .scheduled
            }
            return Match(
                id: event.id,
                league: league,
                kickoff: kickoff,
                state: state,
                detail: status?.shortDetail ?? "",
                home: TeamNames.localized(home.team),
                away: TeamNames.localized(away.team),
                homeScore: state == .scheduled ? nil : home.score,
                awayScore: state == .scheduled ? nil : away.score
            )
        }
    }

    /// ESPN uses `2026-10-31T15:00Z` (no seconds); accept the full form too.
    static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        let short = DateFormatter()
        short.locale = Locale(identifier: "en_US_POSIX")
        short.timeZone = TimeZone(identifier: "UTC")
        short.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        return short.date(from: string)
    }

    // MARK: - Wire format

    struct Scoreboard: Decodable {
        let events: [Event]
    }

    struct Event: Decodable {
        let id: String
        let date: String
        let status: Status?
        let competitions: [Competition]
    }

    struct Competition: Decodable {
        let competitors: [Competitor]
        let status: Status?
    }

    struct Competitor: Decodable {
        let homeAway: String
        let score: String?
        let team: Team
    }

    struct Team: Decodable {
        let displayName: String?
        let shortDisplayName: String?
        let abbreviation: String?
    }

    struct Status: Decodable {
        let type: StatusType
    }

    struct StatusType: Decodable {
        let state: String?
        let shortDetail: String?
    }
}
