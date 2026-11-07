import XCTest
@testable import Tat

@MainActor
final class ReminderStoreTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_793_400_000) // 2026-10-31 08:00 UTC

    private func makeSettings(lead: ReminderLead = .fifteen) -> AppSettings {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "tat.tests.\(UUID().uuidString)")!)
        settings.reminderLead = lead
        return settings
    }

    private func makeStore(
        file: URL? = nil,
        scheduler: RecordingReminderScheduler = RecordingReminderScheduler(),
        settings: AppSettings? = nil
    ) -> ReminderStore {
        ReminderStore(fileURL: file, scheduler: scheduler, settings: settings ?? makeSettings(), now: { [unowned self] in self.clock })
    }

    private func match(
        id: String = "1", league: String = "soccer/eng.1", inMinutes minutes: Double = 120,
        state: Match.State = .scheduled, home: String = "切尔西", away: String = "曼联"
    ) -> Match {
        Match(id: id, league: league, kickoff: clock.addingTimeInterval(minutes * 60), state: state, detail: "",
              home: home, away: away, homeScore: nil, awayScore: nil)
    }

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tat-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("reminders.json")
    }

    func testRingingTheBellAsksPermissionOnceAndSchedulesBeforeKickoff() async {
        let scheduler = RecordingReminderScheduler()
        let store = makeStore(scheduler: scheduler)
        let game = match(inMinutes: 120)

        await store.toggle(game)

        XCTAssertTrue(store.isSet(game))
        XCTAssertEqual(scheduler.requestCount, 1)
        XCTAssertEqual(store.authorization, .authorized)
        let request = scheduler.scheduled["tat.match.soccer/eng.1#1"]
        XCTAssertEqual(request?.date, game.kickoff.addingTimeInterval(-15 * 60))
        XCTAssertEqual(request?.title, "英超 · 15 分钟后开赛")
        XCTAssertTrue(request?.body.hasPrefix("切尔西 vs 曼联 · ") == true)

        await store.toggle(match(id: "2", inMinutes: 200))
        XCTAssertEqual(scheduler.requestCount, 1, "permission is only asked once")
        XCTAssertEqual(scheduler.scheduled.count, 2)
    }

    func testRingingAgainCancels() async {
        let scheduler = RecordingReminderScheduler(status: .authorized)
        let store = makeStore(scheduler: scheduler)
        await store.refreshAuthorization()
        let game = match()
        await store.toggle(game)
        await store.toggle(game)
        XCTAssertFalse(store.isSet(game))
        XCTAssertTrue(scheduler.scheduled.isEmpty)
    }

    func testOnlyUpcomingMatchesCanHaveReminders() async {
        let scheduler = RecordingReminderScheduler(status: .authorized)
        let store = makeStore(scheduler: scheduler)
        for game in [match(state: .live), match(state: .finished), match(inMinutes: -5)] {
            XCTAssertFalse(store.canRemind(game))
            await store.toggle(game)
            XCTAssertFalse(store.isSet(game))
        }
        XCTAssertTrue(scheduler.scheduled.isEmpty)
    }

    func testReminderSetInsideTheLeadTimeFiresRightAway() async {
        let scheduler = RecordingReminderScheduler(status: .authorized)
        let store = makeStore(scheduler: scheduler)
        await store.refreshAuthorization()
        await store.toggle(match(inMinutes: 5))
        let request = scheduler.scheduled.values.first
        XCTAssertEqual(request?.date, clock.addingTimeInterval(1))
        XCTAssertEqual(request?.title, "英超 · 5 分钟后开赛", "says how long is actually left")
    }

    func testAtKickoffAndOneHourWording() async {
        let settings = makeSettings(lead: .atKickoff)
        let scheduler = RecordingReminderScheduler(status: .authorized)
        let store = makeStore(scheduler: scheduler, settings: settings)
        await store.refreshAuthorization()
        let game = match(league: "basketball/nba", inMinutes: 90, home: "湖人", away: "勇士")
        await store.toggle(game)
        XCTAssertEqual(scheduler.scheduled.values.first?.date, game.kickoff)
        XCTAssertEqual(scheduler.scheduled.values.first?.title, "NBA · 即将开赛")

        settings.reminderLead = .hour
        await store.rescheduleAll()
        XCTAssertEqual(scheduler.scheduled.values.first?.date, game.kickoff.addingTimeInterval(-3600))
        XCTAssertEqual(scheduler.scheduled.values.first?.title, "NBA · 1 小时后开赛")
    }

    func testChangingTheLeadTimeMovesEveryReminder() async {
        let settings = makeSettings(lead: .fifteen)
        let scheduler = RecordingReminderScheduler(status: .authorized)
        let store = makeStore(scheduler: scheduler, settings: settings)
        await store.refreshAuthorization()
        let a = match(id: "a", inMinutes: 100)
        let b = match(id: "b", inMinutes: 300)
        await store.toggle(a)
        await store.toggle(b)

        settings.reminderLead = .thirty
        await store.rescheduleAll()
        XCTAssertEqual(scheduler.scheduled["tat.match.soccer/eng.1#a"]?.date, a.kickoff.addingTimeInterval(-1800))
        XCTAssertEqual(scheduler.scheduled["tat.match.soccer/eng.1#b"]?.date, b.kickoff.addingTimeInterval(-1800))
    }

    func testDeniedPermissionKeepsTheBellAndSchedulesOnceAllowed() async {
        let scheduler = RecordingReminderScheduler(grantOnRequest: false)
        let store = makeStore(scheduler: scheduler)
        let game = match()
        await store.toggle(game)
        XCTAssertTrue(store.isSet(game), "the choice is kept")
        XCTAssertEqual(store.authorization, .denied)
        XCTAssertTrue(scheduler.scheduled.isEmpty)

        // The user flips the switch in System Settings and reopens the panel.
        scheduler.status = .authorized
        await store.refreshAuthorization()
        XCTAssertEqual(scheduler.scheduled.count, 1)
    }

    func testSyncFollowsKickoffChangesAndDropsStartedMatches() async {
        let scheduler = RecordingReminderScheduler(status: .authorized)
        let store = makeStore(scheduler: scheduler)
        await store.refreshAuthorization()
        let moved = match(id: "moved", inMinutes: 120)
        let started = match(id: "started", inMinutes: 60)
        await store.toggle(moved)
        await store.toggle(started)

        let postponed = match(id: "moved", inMinutes: 240)
        await store.sync(with: [postponed, match(id: "started", state: .live), match(id: "other")])

        XCTAssertTrue(store.isSet(postponed))
        XCTAssertEqual(scheduler.scheduled["tat.match.soccer/eng.1#moved"]?.date, postponed.kickoff.addingTimeInterval(-900))
        XCTAssertFalse(store.isSet(started))
        XCTAssertNil(scheduler.scheduled["tat.match.soccer/eng.1#started"])
        XCTAssertEqual(store.reminders.count, 1)
    }

    func testSameEventIdInDifferentSportsAreSeparate() async {
        let store = makeStore(scheduler: RecordingReminderScheduler(status: .authorized))
        let soccer = match(id: "42", league: "soccer/eng.1")
        let nba = match(id: "42", league: "basketball/nba")
        await store.toggle(soccer)
        XCTAssertTrue(store.isSet(soccer))
        XCTAssertFalse(store.isSet(nba))
    }

    func testPersistsAndForgetsMatchesThatHaveStarted() async {
        let file = tempFile()
        let first = makeStore(file: file, scheduler: RecordingReminderScheduler(status: .authorized))
        let game = match(inMinutes: 60)
        await first.toggle(game)

        let reloaded = makeStore(file: file)
        XCTAssertTrue(reloaded.isSet(game))
        XCTAssertEqual(reloaded.reminders.values.first?.home, "切尔西")

        clock = clock.addingTimeInterval(2 * 3600)
        let later = makeStore(file: file)
        XCTAssertTrue(later.reminders.isEmpty, "kickoff has passed")
    }
}
