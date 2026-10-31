import Foundation
import Observation

/// Loads the "tips" sections. Only refreshes while the panel is visible, so a hidden
/// panel never touches the network.
@MainActor
@Observable
final class TipsStore {
    enum Phase<Value: Equatable>: Equatable {
        case idle
        case loading
        case loaded(Value)
        case failed(String)
    }

    static let staleAfter: TimeInterval = 180

    private(set) var markets: Phase<[Quote]> = .idle
    private(set) var matches: Phase<[Match]> = .idle
    private(set) var lastUpdated: Date?

    /// Last successful values, kept on screen while a refresh is in flight.
    private(set) var lastQuotes: [Quote] = []
    private(set) var lastMatches: [Match] = []

    @ObservationIgnored private let marketProvider: any MarketProviding
    @ObservationIgnored private let matchProvider: any MatchProviding
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    init(
        settings: AppSettings,
        marketProvider: any MarketProviding = TencentMarketProvider(),
        matchProvider: any MatchProviding = ESPNMatchProvider(),
        now: @escaping () -> Date = Date.init
    ) {
        self.settings = settings
        self.marketProvider = marketProvider
        self.matchProvider = matchProvider
        self.now = now
    }

    var isLoading: Bool { markets == .loading || matches == .loading }

    var isStale: Bool {
        guard let lastUpdated else { return true }
        return now().timeIntervalSince(lastUpdated) > Self.staleAfter
    }

    func refreshIfStale() {
        if isStale { refresh() }
    }

    func refresh() {
        inFlight?.cancel()
        let codes = settings.enabledIndices
        let leagues = settings.enabledLeagues
        let day = now()
        markets = .loading
        matches = .loading
        inFlight = Task { [marketProvider, matchProvider] in
            async let quoteResult = Self.capture { try await marketProvider.quotes(for: codes) }
            async let matchResult = Self.capture { try await matchProvider.matches(leagues: leagues, on: day, calendar: .current) }
            let (quotes, fixtures) = await (quoteResult, matchResult)
            guard !Task.isCancelled else { return }
            apply(quotes: quotes, matches: fixtures)
        }
    }

    private func apply(quotes: Result<[Quote], Error>, matches fixtures: Result<[Match], Error>) {
        switch quotes {
        case .success(let value):
            lastQuotes = value
            markets = .loaded(value)
        case .failure(let error):
            markets = .failed(Self.message(for: error))
        }
        switch fixtures {
        case .success(let value):
            lastMatches = value
            matches = .loaded(value)
        case .failure(let error):
            matches = .failed(Self.message(for: error))
        }
        lastUpdated = now()
    }

    private nonisolated static func capture<T: Sendable>(_ work: @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    private static func message(for error: Error) -> String {
        if let error = error as? TipsError, let text = error.errorDescription { return text }
        if (error as? URLError)?.code == .notConnectedToInternet { return "网络未连接" }
        return "加载失败"
    }
}
