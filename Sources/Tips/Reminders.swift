import Foundation
import Observation
import UserNotifications

/// How long before kickoff a reminder fires (minutes).
enum ReminderLead: Int, CaseIterable, Identifiable, Sendable {
    case atKickoff = 0
    case five = 5
    case fifteen = 15
    case thirty = 30
    case hour = 60

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .atKickoff: "开赛时"
        case .hour: "提前 1 小时"
        default: "提前 \(rawValue) 分钟"
        }
    }

    var interval: TimeInterval { TimeInterval(rawValue * 60) }
}

/// A match the user rang the bell on. Keeps enough to describe the match when the
/// reminder fires, even if the match is no longer in today's list.
struct MatchReminder: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var league: String
    var home: String
    var away: String
    var kickoff: Date

    init(match: Match) {
        id = Self.key(for: match)
        league = match.league
        home = match.home
        away = match.away
        kickoff = match.kickoff
    }

    /// ESPN event ids are only unique within a sport, so prefix the league.
    static func key(for match: Match) -> String { "\(match.league)#\(match.id)" }

    var notificationID: String { "tat.match.\(id)" }
}

enum ReminderAuthorization: Equatable, Sendable {
    case notDetermined, denied, authorized
}

/// The system side of reminders, so the store can be tested without real notifications.
@MainActor
protocol ReminderScheduling: AnyObject {
    func authorization() async -> ReminderAuthorization
    func requestAuthorization() async -> Bool
    func schedule(id: String, title: String, body: String, at date: Date) async
    func cancel(ids: [String])
}

/// Match reminders: which matches have the bell on, and the local notifications behind them.
///
/// Notifications are scheduled with the system, so they fire even if tat isn't running.
/// See docs/DESIGN.md §3.3.
@MainActor
@Observable
final class ReminderStore {
    private(set) var reminders: [String: MatchReminder] = [:]
    private(set) var authorization: ReminderAuthorization = .notDetermined

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let scheduler: any ReminderScheduling
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let now: () -> Date

    init(fileURL: URL?, scheduler: any ReminderScheduling, settings: AppSettings, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.scheduler = scheduler
        self.settings = settings
        self.now = now
        load()
        purgeStarted()
    }

    func isSet(_ match: Match) -> Bool {
        reminders[MatchReminder.key(for: match)] != nil
    }

    /// Only matches that haven't kicked off can get a reminder.
    func canRemind(_ match: Match) -> Bool {
        match.state == .scheduled && match.kickoff > now()
    }

    /// Re-reads the notification permission. If the user just allowed notifications in
    /// System Settings, the reminders that couldn't be scheduled before get scheduled now.
    func refreshAuthorization() async {
        let previous = authorization
        authorization = await scheduler.authorization()
        if authorization == .authorized && previous != .authorized {
            await rescheduleAll()
        }
    }

    /// Rings or silences the bell. Asks for notification permission the first time.
    func toggle(_ match: Match) async {
        let key = MatchReminder.key(for: match)
        if let existing = reminders[key] {
            reminders[key] = nil
            scheduler.cancel(ids: [existing.notificationID])
            save()
            return
        }
        guard canRemind(match) else { return }

        // Show the bell as set right away; the permission prompt can take a while.
        let reminder = MatchReminder(match: match)
        reminders[key] = reminder
        save()

        if authorization == .notDetermined {
            authorization = await scheduler.requestAuthorization() ? .authorized : .denied
        }
        await schedule(reminder)
    }

    /// The lead time changed: move every pending notification.
    func rescheduleAll() async {
        for reminder in reminders.values.sorted(by: { $0.kickoff < $1.kickoff }) {
            await schedule(reminder)
        }
    }

    /// Keep reminders in step with fresh fixtures: follow kickoff changes, and drop
    /// reminders for matches that have started.
    func sync(with matches: [Match]) async {
        var changed: [MatchReminder] = []
        for match in matches {
            let key = MatchReminder.key(for: match)
            guard var reminder = reminders[key] else { continue }
            if match.state != .scheduled {
                reminders[key] = nil
                scheduler.cancel(ids: [reminder.notificationID])
                continue
            }
            let updated = MatchReminder(match: match)
            if updated != reminder {
                reminder = updated
                reminders[key] = reminder
                changed.append(reminder)
            }
        }
        purgeStarted()
        save()
        for reminder in changed {
            await schedule(reminder)
        }
    }

    // MARK: - Notification content

    /// When the notification for `reminder` should fire, or nil if the match has started.
    /// A reminder set later than the lead time (e.g. 5 minutes before kickoff with a
    /// 15-minute lead) fires right away.
    func fireDate(for reminder: MatchReminder) -> Date? {
        let current = now()
        guard reminder.kickoff > current else { return nil }
        return max(reminder.kickoff.addingTimeInterval(-settings.reminderLead.interval), current.addingTimeInterval(1))
    }

    func content(for reminder: MatchReminder, firingAt date: Date) -> (title: String, body: String) {
        let minutes = Int((reminder.kickoff.timeIntervalSince(date) / 60).rounded())
        let when = minutes <= 0 ? "即将开赛" : minutes >= 60 && minutes % 60 == 0 ? "\(minutes / 60) 小时后开赛" : "\(minutes) 分钟后开赛"
        let title = "\(League.named(reminder.league)) · \(when)"
        let body = "\(reminder.home) vs \(reminder.away) · \(Self.time.string(from: reminder.kickoff)) 开球"
        return (title, body)
    }

    private func schedule(_ reminder: MatchReminder) async {
        guard authorization == .authorized, let date = fireDate(for: reminder) else { return }
        let text = content(for: reminder, firingAt: date)
        await scheduler.schedule(id: reminder.notificationID, title: text.title, body: text.body, at: date)
    }

    private func purgeStarted() {
        let current = now()
        let before = reminders.count
        reminders = reminders.filter { $0.value.kickoff > current }
        if reminders.count != before { save() }
    }

    // MARK: - Persistence

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let list = try? Self.decoder.decode([MatchReminder].self, from: data)
        else { return }
        reminders = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let list = reminders.values.sorted { ($0.kickoff, $0.id) < ($1.kickoff, $1.id) }
            try Self.encoder.encode(list).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("tat: failed to save reminders: \(error)")
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

/// Real notifications through `UNUserNotificationCenter`.
@MainActor
final class SystemReminderScheduler: ReminderScheduling {
    private var center: UNUserNotificationCenter { .current() }

    func authorization() async -> ReminderAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .authorized
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func schedule(id: String, title: String, body: String, at date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        // Re-adding with the same identifier replaces the pending request.
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        } catch {
            NSLog("tat: failed to schedule reminder: \(error)")
        }
    }

    func cancel(ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}

/// Records what would be scheduled; used by tests and `-uiTesting` so they never post
/// real notifications.
@MainActor
final class RecordingReminderScheduler: ReminderScheduling {
    var status: ReminderAuthorization
    var grantOnRequest: Bool
    private(set) var scheduled: [String: (title: String, body: String, date: Date)] = [:]
    private(set) var requestCount = 0

    init(status: ReminderAuthorization = .notDetermined, grantOnRequest: Bool = true) {
        self.status = status
        self.grantOnRequest = grantOnRequest
    }

    func authorization() async -> ReminderAuthorization { status }

    func requestAuthorization() async -> Bool {
        requestCount += 1
        status = grantOnRequest ? .authorized : .denied
        return grantOnRequest
    }

    func schedule(id: String, title: String, body: String, at date: Date) async {
        scheduled[id] = (title, body, date)
    }

    func cancel(ids: [String]) {
        for id in ids { scheduled[id] = nil }
    }
}
