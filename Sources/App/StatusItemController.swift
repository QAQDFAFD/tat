import AppKit
import Observation

/// Menu bar icon: left click toggles the panel, right click opens the menu.
/// Shows the number of open todos next to the icon.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let todos: TodoStore
    private let settings: AppSettings
    private let loginItem: LoginItem
    private let onToggle: () -> Void

    init(todos: TodoStore, settings: AppSettings, loginItem: LoginItem, onToggle: @escaping () -> Void) {
        self.todos = todos
        self.settings = settings
        self.loginItem = loginItem
        self.onToggle = onToggle
        super.init()

        if let button = item.button {
            let image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "tat")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityIdentifier("tat.statusItem")
            button.toolTip = "tat — ⌥⌘T"
        }
        observeCount()
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            onToggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let toggle = NSMenuItem(title: "显示 / 隐藏面板", action: #selector(togglePanel), keyEquivalent: "t")
        toggle.keyEquivalentModifierMask = [.command, .option]
        toggle.target = self
        menu.addItem(toggle)

        let pin = NSMenuItem(title: "常驻显示", action: #selector(togglePinned), keyEquivalent: "")
        pin.target = self
        pin.state = settings.isPinned ? .on : .off
        menu.addItem(pin)

        let login = NSMenuItem(title: "开机自动启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = loginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 tat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
        item.button?.performClick(nil)
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            // Detach so the next left click toggles the panel instead of reopening the menu.
            item.menu = nil
        }
    }

    @objc private func togglePanel() { onToggle() }
    @objc private func togglePinned() { settings.isPinned.toggle() }
    @objc private func toggleLaunchAtLogin() { loginItem.isEnabled.toggle() }

    private func observeCount() {
        let count = withObservationTracking {
            todos.openItems.count
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeCount() }
        }
        item.button?.title = count > 0 ? " \(count)" : ""
        item.button?.setAccessibilityLabel(count > 0 ? "tat，\(count) 项待办" : "tat")
    }
}
