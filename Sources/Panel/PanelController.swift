import AppKit
import Observation
import SwiftUI

/// Borderless floating panel that never activates the app on its own; it only takes
/// keyboard focus when the user clicks into it or summons it with the hotkey.
final class EdgePanel: NSPanel {
    var onEscape: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        setAccessibilityIdentifier("tat.panel")
        setAccessibilityTitle("tat")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

/// UI state that outlives a single show/hide of the panel.
@MainActor
@Observable
final class PanelUIState {
    var draft = ""
    var showingSettings = false
    var completedExpanded = false
    /// Bumped to ask the input field to take focus.
    var focusRequest = 0

    /// Don't auto-hide while the user has typed something they haven't submitted.
    var holdOpen: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct PanelActions: Sendable {
    var dismiss: @MainActor @Sendable () -> Void = {}
    var quit: @MainActor @Sendable () -> Void = {}
    var setLaunchAtLogin: @MainActor @Sendable (Bool) -> Void = { _ in }
    var launchAtLogin: @MainActor @Sendable () -> Bool = { false }
}

extension EnvironmentValues {
    @Entry var panelActions = PanelActions()
}

/// Owns the panel window: positioning, slide in/out, and the edge-hover trigger.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let width: CGFloat = 320
    static let margin: CGFloat = 8
    static let cornerRadius: CGFloat = 14

    let panel = EdgePanel()
    private let settings: AppSettings
    private let tips: TipsStore
    private let ui: PanelUIState

    private var trigger = EdgeTrigger()
    private var monitors: [Any] = []
    private var recheckTimer: Timer?
    private var refreshTimer: Timer?
    private var targetFrame: CGRect = .zero
    private var screenFrame: CGRect?
    /// When the panel last hid because it lost focus. Clicking the menu bar icon first takes
    /// focus (hiding the panel) and then toggles; that toggle must not bring it right back.
    private var hiddenOnResignAt: Date?

    private(set) var isShown = false
    var onVisibilityChange: ((Bool) -> Void)?

    init(rootView: some View, settings: AppSettings, tips: TipsStore, ui: PanelUIState) {
        self.settings = settings
        self.tips = tips
        self.ui = ui
        super.init()

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: Self.cornerRadius)

        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        panel.contentView = effect
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.dismiss() }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        observePinned()
    }

    // MARK: - Public

    func startMonitoring() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseUp, .rightMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.evaluate() }
            return event
        }) {
            monitors.append(local)
        }
    }

    /// Hotkey / menu bar: show on the screen under the mouse and focus the input, or hide.
    func toggle() {
        if !isShown, let hiddenAt = hiddenOnResignAt, Date().timeIntervalSince(hiddenAt) < 0.5 {
            hiddenOnResignAt = nil
            return
        }
        if isShown && !settings.isPinned {
            hide()
        } else {
            show(on: Self.screenUnderMouse(), viaHover: false, focusInput: true)
        }
    }

    /// Esc: hide unless pinned.
    func dismiss() {
        guard !settings.isPinned else { return }
        hide()
    }

    func show(on screen: NSScreen?, viaHover: Bool, focusInput: Bool) {
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = Self.panelFrame(in: screen.visibleFrame)
        targetFrame = frame
        screenFrame = screen.frame
        trigger.panelDidShow(viaHover: viaHover)

        if focusInput {
            panel.makeKey()
            ui.showingSettings = false
            ui.focusRequest += 1
        }
        guard !isShown else {
            panel.setFrame(frame, display: true)
            return
        }

        isShown = true
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(reduceMotion ? frame : frame.offsetBy(dx: 24, dy: 0), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        if focusInput { panel.makeKey() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }

        tips.refreshIfStale()
        startRefreshTimer()
        onVisibilityChange?(true)
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        trigger.panelDidHide()
        stopRefreshTimer()
        recheckTimer?.invalidate()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let end = reduceMotion ? targetFrame : targetFrame.offsetBy(dx: 24, dy: 0)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(end, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isShown else { return }
                self.panel.orderOut(nil)
            }
        })
        onVisibilityChange?(false)
    }

    // MARK: - Edge trigger

    private func evaluate() {
        recheckTimer?.invalidate()
        recheckTimer = nil
        trigger.config.showDelay = settings.triggerDelay.rawValue

        let action = trigger.update(
            mouse: NSEvent.mouseLocation,
            now: Date(),
            screens: NSScreen.screens.map { EdgeTrigger.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame) },
            panelFrame: isShown ? targetFrame : nil,
            holdOpen: settings.isPinned || ui.holdOpen,
            buttonsDown: NSEvent.pressedMouseButtons != 0
        )
        switch action {
        case .none:
            break
        case .show(let screen):
            show(on: NSScreen.screens.first { $0.frame == screen.frame }, viaHover: true, focusInput: false)
        case .hide:
            hide()
        case .recheck(let delay):
            recheckTimer = Timer.scheduledTimer(withTimeInterval: delay + 0.01, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
        }
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated {
            // Clicked somewhere else after summoning with the hotkey.
            guard isShown, !settings.isPinned, !ui.holdOpen,
                  !targetFrame.insetBy(dx: -16, dy: -16).contains(NSEvent.mouseLocation)
            else { return }
            hiddenOnResignAt = Date()
            hide()
        }
    }

    // MARK: - Helpers

    private func observePinned() {
        withObservationTracking {
            _ = settings.isPinned
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.settings.isPinned && !self.isShown {
                    self.show(on: Self.screenUnderMouse(), viaHover: false, focusInput: false)
                }
                self.observePinned()
            }
        }
    }

    @objc private func screensChanged() {
        guard isShown else { return }
        let screen = NSScreen.screens.first { $0.frame == screenFrame } ?? NSScreen.main
        guard let screen else { return }
        targetFrame = Self.panelFrame(in: screen.visibleFrame)
        screenFrame = screen.frame
        panel.setFrame(targetFrame, display: true)
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: TipsStore.staleAfter, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tips.refresh() }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// A card in the top-right corner (under the menu bar, like Notification Center),
    /// tall enough for a day's todos and tips; anything longer scrolls.
    static func panelFrame(in visible: CGRect) -> CGRect {
        let height = min(maxHeight, max(visible.height - margin * 2, 200))
        return CGRect(
            x: visible.maxX - width - margin,
            y: visible.maxY - margin - height,
            width: width,
            height: height
        )
    }

    static let maxHeight: CGFloat = 680

    static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
