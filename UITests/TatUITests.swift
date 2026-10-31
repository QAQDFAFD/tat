import AppKit
import XCTest

/// End-to-end tests: launch the real app, drive it with the mouse and keyboard.
/// `-uiTesting` gives the app throwaway preferences and stubbed tips data.
final class TatUITests: XCTestCase {
    private var app: XCUIApplication!
    private var dataDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        dataDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tat-uitests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: dataDirectory)
    }

    // MARK: - Todo

    func testAddCompleteDeleteAndClearTodos() {
        launch(showPanel: true, pinned: true)
        let input = todoInput
        XCTAssertTrue(input.waitForExistence(timeout: 5))

        input.click()
        input.typeText("买牛奶\n")
        input.typeText("回复邮件\n")

        XCTAssertTrue(waitForCount(of: rows("todo.row"), toBe: 2))
        XCTAssertEqual(input.value as? String ?? "", "", "input clears after submit")
        XCTAssertEqual(titles().first, "回复邮件", "newest first")
        settle()

        // Complete one.
        element(.button, label: "完成：买牛奶").click()
        XCTAssertTrue(waitForCount(of: rows("todo.row"), toBe: 1))
        let completedToggle = element(.button, label: "展开已完成，共 1 项")
        XCTAssertTrue(completedToggle.waitForExistence(timeout: 2))
        settle()

        // Expand completed and undo.
        completedToggle.click()
        let undo = element(.button, label: "标记未完成：买牛奶")
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        undo.click()
        XCTAssertTrue(waitForCount(of: rows("todo.row"), toBe: 2))
        settle()

        // Delete via the hover button.
        let row = rows("todo.row").element(boundBy: 0)
        row.hover()
        element(.button, label: "删除：回复邮件").click()
        XCTAssertTrue(waitForCount(of: rows("todo.row"), toBe: 1))
        settle()

        // Complete the last one, then clear completed.
        element(.button, label: "完成：买牛奶").click()
        XCTAssertTrue(app.staticTexts["全部完成，干得漂亮"].waitForExistence(timeout: 2))
        settle()
        app.buttons["todo.clearCompleted"].click()
        XCTAssertTrue(app.staticTexts["今天还没有待办"].waitForExistence(timeout: 2))
    }

    func testBlankInputIsIgnored() {
        launch(showPanel: true, pinned: true)
        let input = todoInput
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.click()
        input.typeText("   \n")
        XCTAssertEqual(rows("todo.row").count, 0)
        XCTAssertTrue(app.staticTexts["今天还没有待办"].exists)
    }

    func testTodosPersistAcrossLaunches() {
        launch(showPanel: true, pinned: true)
        XCTAssertTrue(todoInput.waitForExistence(timeout: 5))
        todoInput.click()
        todoInput.typeText("持久化测试\n")
        XCTAssertTrue(waitForCount(of: rows("todo.row"), toBe: 1))
        app.terminate()

        launch(showPanel: true, pinned: true)
        XCTAssertTrue(todoInput.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForCount(of: rows("todo.row"), toBe: 1))
        XCTAssertEqual(titles(), ["持久化测试"])
    }

    // MARK: - Tips

    func testTipsShowMarketsAndMatches() {
        launch(showPanel: true, pinned: true)
        XCTAssertTrue(waitForCount(of: rows("market.row"), toBe: 7))
        XCTAssertTrue(element(.any, labelContains: "上证指数 3599.02 下跌 1.44%").exists)
        XCTAssertTrue(element(.any, labelContains: "恒生指数 23294.42 上涨 1.46%").exists)

        XCTAssertTrue(waitForCount(of: rows("match.row"), toBe: 3))
        XCTAssertTrue(element(.any, labelContains: "进行中 67' 曼城 1 比 1 布莱顿").exists)
        XCTAssertTrue(element(.any, labelContains: "完场 切尔西 2 比 1 曼联").exists)

        todoInput.click()
        todoInput.typeText("回复邮件\n")
        todoInput.typeText("看英超\n")
        XCTAssertTrue(waitForCount(of: rows("todo.row"), toBe: 2), "rows: \(titles())")
        settle()
        element(.button, label: "完成：回复邮件").click()
        XCTAssertTrue(waitForCount(of: rows("todo.row"), toBe: 1), "rows: \(titles())")
        attachScreenshot(named: "panel")

        app.buttons["header.settings"].click()
        XCTAssertTrue(app.checkBoxes["settings.index.usDJI"].waitForExistence(timeout: 2))
        attachScreenshot(named: "settings")
    }

    func testSettingsChangeWhichTipsAreShown() {
        launch(showPanel: true, pinned: true)
        XCTAssertTrue(waitForCount(of: rows("market.row"), toBe: 7))

        app.buttons["header.settings"].click()
        let dow = app.checkBoxes["settings.index.usDJI"]
        XCTAssertTrue(dow.waitForExistence(timeout: 2))
        dow.click()
        app.checkBoxes["settings.league.soccer/eng.1"].click()
        app.buttons["header.settings"].click()

        XCTAssertTrue(waitForCount(of: rows("market.row"), toBe: 6))
        XCTAssertFalse(element(.any, labelContains: "道琼斯").exists)
        XCTAssertEqual(rows("match.row").count, 0, "no league selected hides the matches section")
    }

    // MARK: - Panel behaviour

    func testRightEdgeHoverShowsAndLeavingHidesThePanel() throws {
        launch(showPanel: false)
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        let screen = try XCTUnwrap(NSScreen.main?.frame)

        // Park the mouse in the middle first so a cursor left at the edge doesn't count.
        hover(statusItem, toScreenPoint: CGPoint(x: screen.width / 2, y: screen.height / 2))
        XCTAssertFalse(todoInput.exists)

        hover(statusItem, toScreenPoint: CGPoint(x: screen.width - 1, y: screen.height / 2))
        XCTAssertTrue(todoInput.waitForExistence(timeout: 3), "panel slides in at the right edge")

        hover(statusItem, toScreenPoint: CGPoint(x: screen.width / 3, y: screen.height / 2))
        XCTAssertTrue(waitForNonExistence(todoInput, timeout: 3), "panel hides after the mouse leaves")
    }

    func testPinnedPanelStaysWhenMouseLeaves() throws {
        launch(showPanel: true)
        XCTAssertTrue(todoInput.waitForExistence(timeout: 5))
        let pin = app.buttons["header.pin"]
        pin.click()
        XCTAssertEqual(pin.label, "取消常驻")

        let screen = try XCTUnwrap(NSScreen.main?.frame)
        hover(app.statusItems.firstMatch, toScreenPoint: CGPoint(x: screen.width / 3, y: screen.height / 2))
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(todoInput.exists, "pinned panel never auto-hides")

        pin.click()
        XCTAssertEqual(pin.label, "常驻显示")
    }

    func testStatusItemTogglesThePanel() throws {
        launch(showPanel: false)
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        XCTAssertFalse(todoInput.exists)
        // On a crowded notched menu bar macOS hides new status items behind the notch.
        try XCTSkipUnless(statusItem.isHittable, "menu bar is full, status item is hidden")

        statusItem.click()
        XCTAssertTrue(todoInput.waitForExistence(timeout: 3))

        statusItem.click()
        XCTAssertTrue(waitForNonExistence(todoInput, timeout: 3))
    }

    func testHotKeyTogglesThePanelAndFocusesInput() {
        launch(showPanel: false)
        XCTAssertTrue(app.statusItems.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(todoInput.exists)

        app.typeKey("t", modifierFlags: [.command, .option])
        XCTAssertTrue(todoInput.waitForExistence(timeout: 3))

        // The input has focus: typing goes straight in.
        app.typeText("快捷键添加\n")
        XCTAssertTrue(waitForCount(of: rows("todo.row"), toBe: 1))

        app.typeKey("t", modifierFlags: [.command, .option])
        XCTAssertTrue(waitForNonExistence(todoInput, timeout: 3))
    }

    func testEscapeHidesUnpinnedPanel() {
        launch(showPanel: true)
        XCTAssertTrue(todoInput.waitForExistence(timeout: 5))
        todoInput.click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNonExistence(todoInput, timeout: 3))
    }

    // MARK: - Helpers

    private var todoInput: XCUIElement { app.textFields["todo.input"] }

    private func launch(showPanel: Bool, pinned: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + (showPanel ? ["-showPanel"] : []) + (pinned ? ["-pinned"] : [])
        app.launchEnvironment["TAT_DATA_DIR"] = dataDirectory.path
        app.launch()
    }

    private func rows(_ identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    private func titles() -> [String] {
        app.staticTexts.matching(identifier: "todo.title").allElementsBoundByIndex.map { element in
            (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
        }
    }

    private func element(_ type: XCUIElement.ElementType, label: String) -> XCUIElement {
        app.descendants(matching: type).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func element(_ type: XCUIElement.ElementType, labelContains text: String) -> XCUIElement {
        app.descendants(matching: type).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Moves the mouse to an absolute point (top-left origin, main display), using an
    /// always-present element as the anchor for XCUICoordinate.
    private func hover(_ anchor: XCUIElement, toScreenPoint point: CGPoint) {
        let origin = anchor.frame.origin
        anchor.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x - origin.x, dy: point.y - origin.y))
            .hover()
    }

    /// Lets list insert/remove animations finish so clicks land on the final layout.
    private func settle() {
        Thread.sleep(forTimeInterval: 0.35)
    }

    /// Keeps a screenshot of the panel in the test report (handy for reviewing UI changes in CI).
    private func attachScreenshot(named name: String) {
        Thread.sleep(forTimeInterval: 0.4) // let animations settle
        let panel = app.dialogs["tat.panel"]
        let shot = panel.exists ? panel.screenshot() : XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForCount(of query: XCUIElementQuery, toBe expected: Int, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "count == %d", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: query)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
