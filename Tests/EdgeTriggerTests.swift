import XCTest
@testable import Tat

final class EdgeTriggerTests: XCTestCase {
    // A 1440×900 main screen with a 25pt menu bar.
    private let main = EdgeTrigger.Screen(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
    )
    // A second display placed to the right of the main one.
    private let right = EdgeTrigger.Screen(
        frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    )
    private let t0 = Date(timeIntervalSince1970: 0)
    private let panel = CGRect(x: 1440 - 328, y: 8, width: 320, height: 859)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func hidden(
        _ trigger: inout EdgeTrigger, _ point: CGPoint, _ time: TimeInterval,
        screens: [EdgeTrigger.Screen]? = nil, buttonsDown: Bool = false
    ) -> EdgeTrigger.Action {
        trigger.update(mouse: point, now: at(time), screens: screens ?? [main], panelFrame: nil, holdOpen: false, buttonsDown: buttonsDown)
    }

    private func visible(
        _ trigger: inout EdgeTrigger, _ point: CGPoint, _ time: TimeInterval, holdOpen: Bool = false
    ) -> EdgeTrigger.Action {
        trigger.update(mouse: point, now: at(time), screens: [main], panelFrame: panel, holdOpen: holdOpen, buttonsDown: false)
    }

    // MARK: - Showing

    func testShowsAfterDwellingAtRightEdge() {
        var trigger = EdgeTrigger()
        let edge = CGPoint(x: 1439.5, y: 400)
        XCTAssertEqual(hidden(&trigger, edge, 0), .recheck(after: 0.15))
        if case .recheck(let remaining) = hidden(&trigger, edge, 0.1) {
            XCTAssertEqual(remaining, 0.05, accuracy: 0.0001)
        } else {
            XCTFail("expected recheck")
        }
        XCTAssertEqual(hidden(&trigger, edge, 0.16), .show(main))
    }

    func testZeroDelayShowsImmediately() {
        var trigger = EdgeTrigger()
        trigger.config.showDelay = 0
        XCTAssertEqual(hidden(&trigger, CGPoint(x: 1440, y: 400), 0), .show(main))
    }

    func testLeavingTheEdgeResetsTheDwell() {
        var trigger = EdgeTrigger()
        _ = hidden(&trigger, CGPoint(x: 1439.5, y: 400), 0)
        XCTAssertEqual(hidden(&trigger, CGPoint(x: 1200, y: 400), 0.1), .none)
        XCTAssertEqual(hidden(&trigger, CGPoint(x: 1439.5, y: 400), 0.2), .recheck(after: 0.15))
    }

    func testAwayFromEdgeDoesNothing() {
        var trigger = EdgeTrigger()
        XCTAssertEqual(hidden(&trigger, CGPoint(x: 1430, y: 400), 0), .none)
    }

    func testDraggingAcrossTheEdgeDoesNotTrigger() {
        var trigger = EdgeTrigger()
        XCTAssertEqual(hidden(&trigger, CGPoint(x: 1439.5, y: 400), 0, buttonsDown: true), .none)
        XCTAssertEqual(hidden(&trigger, CGPoint(x: 1439.5, y: 400), 1, buttonsDown: true), .none)
    }

    func testMenuBarCornerAndBottomCornerAreIgnored() {
        var trigger = EdgeTrigger()
        XCTAssertEqual(hidden(&trigger, CGPoint(x: 1439.5, y: 890), 0), .none, "menu bar / Control Center")
        XCTAssertEqual(hidden(&trigger, CGPoint(x: 1439.5, y: 2), 0), .none, "bottom-right hot corner")
    }

    func testSharedEdgeBetweenDisplaysDoesNotTrigger() {
        var trigger = EdgeTrigger()
        let point = CGPoint(x: 1439.5, y: 400)
        XCTAssertEqual(hidden(&trigger, point, 0, screens: [main, right]), .none)
        XCTAssertEqual(hidden(&trigger, point, 1, screens: [main, right]), .none)
    }

    func testOuterEdgeOfRightDisplayTriggers() {
        var trigger = EdgeTrigger()
        trigger.config.showDelay = 0
        XCTAssertEqual(hidden(&trigger, CGPoint(x: 3359.5, y: 500), 0, screens: [main, right]), .show(right))
    }

    func testEdgeAboveTheNeighbouringDisplayStillTriggers() {
        // Main screen is taller than its right-hand neighbour: the part above the neighbour is an outer edge.
        let tall = EdgeTrigger.Screen(frame: CGRect(x: 0, y: 0, width: 1440, height: 1600),
                                      visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 1575))
        var trigger = EdgeTrigger()
        trigger.config.showDelay = 0
        XCTAssertEqual(hidden(&trigger, CGPoint(x: 1439.5, y: 1300), 0, screens: [tall, right]), .show(tall))
    }

    // MARK: - Hiding

    func testHidesAfterLeavingThePanel() {
        var trigger = EdgeTrigger()
        trigger.panelDidShow(viaHover: true)
        XCTAssertEqual(visible(&trigger, CGPoint(x: 1300, y: 400), 0), .none)
        XCTAssertEqual(visible(&trigger, CGPoint(x: 600, y: 400), 1), .recheck(after: 0.4))
        XCTAssertEqual(visible(&trigger, CGPoint(x: 600, y: 400), 1.41), .hide)
    }

    func testSmallOvershootPastThePanelDoesNotHide() {
        var trigger = EdgeTrigger()
        trigger.panelDidShow(viaHover: true)
        XCTAssertEqual(visible(&trigger, CGPoint(x: panel.minX - 10, y: 400), 0), .none)
    }

    func testComingBackCancelsTheHide() {
        var trigger = EdgeTrigger()
        trigger.panelDidShow(viaHover: true)
        _ = visible(&trigger, CGPoint(x: 600, y: 400), 0)
        XCTAssertEqual(visible(&trigger, CGPoint(x: 1300, y: 400), 0.2), .none)
        XCTAssertEqual(visible(&trigger, CGPoint(x: 600, y: 400), 0.5), .recheck(after: 0.4))
    }

    func testHoldOpenPreventsHiding() {
        var trigger = EdgeTrigger()
        trigger.panelDidShow(viaHover: true)
        XCTAssertEqual(visible(&trigger, CGPoint(x: 600, y: 400), 0, holdOpen: true), .none)
        XCTAssertEqual(visible(&trigger, CGPoint(x: 600, y: 400), 5, holdOpen: true), .none)
    }

    func testHotkeyPanelOnlyAutoHidesAfterTheMouseVisitedIt() {
        var trigger = EdgeTrigger()
        trigger.panelDidShow(viaHover: false)
        XCTAssertEqual(visible(&trigger, CGPoint(x: 600, y: 400), 0), .none)
        XCTAssertEqual(visible(&trigger, CGPoint(x: 600, y: 400), 5), .none)
        XCTAssertFalse(trigger.armed)

        XCTAssertEqual(visible(&trigger, CGPoint(x: 1300, y: 400), 6), .none)
        XCTAssertTrue(trigger.armed)
        XCTAssertEqual(visible(&trigger, CGPoint(x: 600, y: 400), 7), .recheck(after: 0.4))
    }

    func testResetOnHide() {
        var trigger = EdgeTrigger()
        trigger.panelDidShow(viaHover: true)
        _ = visible(&trigger, CGPoint(x: 600, y: 400), 0)
        trigger.panelDidHide()
        XCTAssertNil(trigger.leftPanelAt)
        XCTAssertFalse(trigger.armed)
    }
}
