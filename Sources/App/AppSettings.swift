import Foundation
import Observation

/// User preferences, backed by UserDefaults.
@MainActor
@Observable
final class AppSettings {
    enum TriggerDelay: Double, CaseIterable, Identifiable {
        case instant = 0
        case short = 0.15
        case long = 0.4

        var id: Double { rawValue }

        var title: String {
            switch self {
            case .instant: "立即"
            case .short: "150ms"
            case .long: "400ms"
            }
        }
    }

    var isPinned: Bool {
        didSet { defaults.set(isPinned, forKey: Keys.isPinned) }
    }

    var triggerDelay: TriggerDelay {
        didSet { defaults.set(triggerDelay.rawValue, forKey: Keys.triggerDelay) }
    }

    /// Tencent quote codes, in catalog order.
    var enabledIndices: [String] {
        didSet { defaults.set(enabledIndices, forKey: Keys.enabledIndices) }
    }

    /// ESPN league paths, in catalog order.
    var enabledLeagues: [String] {
        didSet { defaults.set(enabledLeagues, forKey: Keys.enabledLeagues) }
    }

    /// Chinese convention (red = up) when true; western convention (green = up) when false.
    var redMeansUp: Bool {
        didSet { defaults.set(redMeansUp, forKey: Keys.redMeansUp) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        isPinned = defaults.bool(forKey: Keys.isPinned)
        triggerDelay = TriggerDelay(rawValue: defaults.object(forKey: Keys.triggerDelay) as? Double ?? -1) ?? .short
        enabledIndices = defaults.stringArray(forKey: Keys.enabledIndices) ?? MarketIndex.defaultCodes
        enabledLeagues = defaults.stringArray(forKey: Keys.enabledLeagues) ?? League.defaultPaths
        redMeansUp = defaults.object(forKey: Keys.redMeansUp) as? Bool ?? true
    }

    func setIndex(_ code: String, enabled: Bool) {
        enabledIndices = MarketIndex.catalog.map(\.code).filter { $0 == code ? enabled : enabledIndices.contains($0) }
    }

    func setLeague(_ path: String, enabled: Bool) {
        enabledLeagues = League.catalog.map(\.path).filter { $0 == path ? enabled : enabledLeagues.contains($0) }
    }

    private enum Keys {
        static let isPinned = "isPinned"
        static let triggerDelay = "triggerDelay"
        static let enabledIndices = "enabledIndices"
        static let enabledLeagues = "enabledLeagues"
        static let redMeansUp = "redMeansUp"
    }
}
