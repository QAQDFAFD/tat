import AppKit
import SwiftUI
import UserNotifications

/// Launch arguments understood by the app (used by the UI tests):
/// - `-uiTesting`: throwaway preferences, stubbed tips, no login-item changes.
/// - `-showPanel`: show the panel right after launch.
/// - `-pinned` (with `-uiTesting`): start pinned, so stray mouse movement can't hide the panel mid-test.
/// - `TAT_DATA_DIR` (environment): where `todos.json` lives.
struct LaunchOptions {
    var uiTesting: Bool
    var showPanel: Bool
    var pinned: Bool
    var dataDirectory: URL

    static func current(_ info: ProcessInfo = .processInfo) -> LaunchOptions {
        let arguments = info.arguments
        let uiTesting = arguments.contains("-uiTesting")
        let directory: URL
        if let custom = info.environment["TAT_DATA_DIR"], !custom.isEmpty {
            directory = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            directory = support.appendingPathComponent("tat", isDirectory: true)
        }
        return LaunchOptions(
            uiTesting: uiTesting,
            showPanel: arguments.contains("-showPanel"),
            pinned: uiTesting && arguments.contains("-pinned"),
            dataDirectory: directory
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var todos: TodoStore?
    private var reminders: ReminderStore?
    private var panel: PanelController?
    private var statusItem: StatusItemController?
    private var hotKey: GlobalHotKey?
    private let notificationRouter = NotificationRouter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosted unit tests load the app as a test host; don't put UI on screen for them.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }

        let options = LaunchOptions.current()
        let defaults: UserDefaults
        if options.uiTesting, let suite = UserDefaults(suiteName: "io.github.qaqdfafd.tat.uitesting") {
            suite.removePersistentDomain(forName: "io.github.qaqdfafd.tat.uitesting")
            defaults = suite
        } else {
            defaults = .standard
        }

        let settings = AppSettings(defaults: defaults)
        if options.pinned { settings.isPinned = true }
        let todos = TodoStore(fileURL: options.dataDirectory.appendingPathComponent("todos.json"))
        let tips = options.uiTesting
            ? TipsStore(settings: settings, marketProvider: StubMarketProvider(), matchProvider: StubMatchProvider())
            : TipsStore(settings: settings)
        let ui = PanelUIState()
        let loginItem = LoginItem(isAvailable: !options.uiTesting)
        let reminders = ReminderStore(
            fileURL: options.dataDirectory.appendingPathComponent("reminders.json"),
            scheduler: options.uiTesting ? RecordingReminderScheduler(status: .authorized) : SystemReminderScheduler(),
            settings: settings
        )

        var actions = PanelActions()
        actions.quit = { NSApp.terminate(nil) }
        actions.launchAtLogin = { loginItem.isEnabled }
        actions.setLaunchAtLogin = { loginItem.isEnabled = $0 }

        // `panel` is created below; the dismiss action looks it up lazily.
        actions.dismiss = { [weak self] in self?.panel?.dismiss() }

        let root = RootView()
            .environment(todos)
            .environment(tips)
            .environment(settings)
            .environment(ui)
            .environment(reminders)
            .environment(\.panelActions, actions)

        let panel = PanelController(rootView: root, settings: settings, tips: tips, ui: ui)
        panel.startMonitoring()
        panel.onVisibilityChange = { visible in
            // Pick up a permission change made in System Settings while we were hidden.
            if visible { Task { await reminders.refreshAuthorization() } }
        }

        self.todos = todos
        self.reminders = reminders
        self.panel = panel
        Task { await reminders.refreshAuthorization() }
        if !options.uiTesting {
            notificationRouter.onOpen = { [weak panel] in
                panel?.show(on: PanelController.screenUnderMouse(), viaHover: false, focusInput: false)
            }
            UNUserNotificationCenter.current().delegate = notificationRouter
        }
        statusItem = StatusItemController(todos: todos, settings: settings, loginItem: loginItem) { [weak panel] in
            panel?.toggle()
        }
        hotKey = GlobalHotKey { [weak panel] in panel?.toggle() }

        // `.NSCalendarDayChanged` is posted on a background thread. A selector-based observer
        // would call a @MainActor method off the main thread, which Swift 6 traps on (tat used
        // to crash every midnight). Deliver it on the main queue instead.
        NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak todos] _ in
            MainActor.assumeIsolated { todos?.rollOverIfNeeded() }
        }

        if settings.isPinned || options.showPanel {
            panel.show(on: NSScreen.main, viaHover: false, focusInput: false)
        }
    }
}

/// Shows match reminders as banners even while tat is running, and opens the panel
/// when one is clicked.
@MainActor
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: (() -> Void)?

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { onOpen?() }
    }
}
