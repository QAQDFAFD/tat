import CoreGraphics
import Foundation

/// Decides when the edge panel should appear and disappear. Pure logic, no AppKit:
/// the controller feeds it mouse positions and times, and acts on the returned `Action`.
///
/// All rects use Cocoa screen coordinates (origin bottom-left, y grows upward).
struct EdgeTrigger {
    struct Screen: Equatable {
        var frame: CGRect
        var visibleFrame: CGRect
    }

    struct Config {
        /// How close to the right edge (in points) counts as "at the edge".
        var edgeWidth: CGFloat = 2
        var showDelay: TimeInterval = 0.15
        var hideDelay: TimeInterval = 0.4
        /// Slack around the panel before the mouse counts as having left it.
        var hideMargin: CGFloat = 16
        /// Ignore the bottom-right corner so hot corners keep working.
        var bottomCornerExclusion: CGFloat = 6
    }

    enum Action: Equatable {
        case none
        case show(Screen)
        case hide
        /// Nothing to do yet; call `update` again after this many seconds.
        case recheck(after: TimeInterval)
    }

    var config = Config()

    private(set) var edgeEnteredAt: Date?
    private(set) var leftPanelAt: Date?
    /// Auto-hide only starts once the mouse has been inside the panel. A panel opened with
    /// the hotkey while the mouse is elsewhere must not vanish immediately.
    private(set) var armed = false

    mutating func panelDidShow(viaHover: Bool) {
        armed = viaHover
        edgeEnteredAt = nil
        leftPanelAt = nil
    }

    mutating func panelDidHide() {
        armed = false
        edgeEnteredAt = nil
        leftPanelAt = nil
    }

    /// - Parameters:
    ///   - panelFrame: the panel's frame when visible, `nil` when hidden.
    ///   - holdOpen: pinned, or the user is in the middle of something (typing, a menu).
    ///   - buttonsDown: a mouse button is pressed (dragging a window or a file).
    mutating func update(
        mouse: CGPoint,
        now: Date,
        screens: [Screen],
        panelFrame: CGRect?,
        holdOpen: Bool,
        buttonsDown: Bool
    ) -> Action {
        guard let panelFrame else {
            leftPanelAt = nil
            guard !buttonsDown, let screen = Self.edgeScreen(at: mouse, in: screens, config: config) else {
                edgeEnteredAt = nil
                return .none
            }
            let enteredAt = edgeEnteredAt ?? now
            edgeEnteredAt = enteredAt
            let waited = now.timeIntervalSince(enteredAt)
            if waited >= config.showDelay {
                edgeEnteredAt = nil
                return .show(screen)
            }
            return .recheck(after: config.showDelay - waited)
        }

        edgeEnteredAt = nil
        let inside = panelFrame.insetBy(dx: -config.hideMargin, dy: -config.hideMargin).contains(mouse)
            || Self.edgeScreen(at: mouse, in: screens, config: config).map { $0.frame.intersects(panelFrame) } == true
        if inside { armed = true }

        guard armed, !holdOpen, !inside else {
            leftPanelAt = nil
            return .none
        }
        let leftAt = leftPanelAt ?? now
        leftPanelAt = leftAt
        let waited = now.timeIntervalSince(leftAt)
        if waited >= config.hideDelay {
            leftPanelAt = nil
            return .hide
        }
        return .recheck(after: config.hideDelay - waited)
    }

    /// The screen whose *outer* right edge is under the mouse, if any.
    /// An edge shared with another display to the right is not an edge.
    static func edgeScreen(at mouse: CGPoint, in screens: [Screen], config: Config) -> Screen? {
        guard let screen = screens.first(where: { containsInclusive($0.frame, mouse) }) else { return nil }
        let frame = screen.frame
        guard mouse.x >= frame.maxX - config.edgeWidth,
              mouse.y > frame.minY + config.bottomCornerExclusion,
              mouse.y < screen.visibleFrame.maxY // skip the menu bar / Control Center corner
        else { return nil }
        let hasNeighbourOnRight = screens.contains { other in
            other != screen
                && abs(other.frame.minX - frame.maxX) <= 1
                && mouse.y >= other.frame.minY && mouse.y < other.frame.maxY
        }
        return hasNeighbourOnRight ? nil : screen
    }

    /// `NSEvent.mouseLocation` can report exactly `maxX`/`maxY` at the far edge.
    private static func containsInclusive(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }
}
