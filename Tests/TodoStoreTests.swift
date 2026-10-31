import XCTest
@testable import Tat

@MainActor
final class TodoStoreTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_793_400_000) // 2026-10-31

    private func makeStore(file: URL? = nil) -> TodoStore {
        TodoStore(fileURL: file, now: { [unowned self] in self.clock }, calendar: Self.calendar)
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tat-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("todos.json")
    }

    func testAddTrimsAndIgnoresBlankInput() {
        let store = makeStore()
        XCTAssertNil(store.add("   \n "))
        let item = store.add("  买牛奶  ")
        XCTAssertEqual(item?.title, "买牛奶")
        XCTAssertEqual(store.openItems.map(\.title), ["买牛奶"])
    }

    func testAddCapsTitleLength() {
        let store = makeStore()
        let item = store.add(String(repeating: "a", count: 500))
        XCTAssertEqual(item?.title.count, TodoStore.maxTitleLength)
    }

    func testOpenItemsAreNewestFirstEvenWithinTheSameSecond() {
        let store = makeStore()
        store.add("one")
        store.add("two")
        store.add("three")
        XCTAssertEqual(store.openItems.map(\.title), ["three", "two", "one"])
    }

    func testToggleMovesItemBetweenOpenAndCompleted() throws {
        let store = makeStore()
        let item = try XCTUnwrap(store.add("写周报"))
        store.toggle(item.id)
        XCTAssertTrue(store.openItems.isEmpty)
        XCTAssertEqual(store.completedItems.map(\.title), ["写周报"])
        XCTAssertEqual(store.completedItems.first?.completedAt, clock)

        store.toggle(item.id)
        XCTAssertEqual(store.openItems.map(\.title), ["写周报"])
        XCTAssertTrue(store.completedItems.isEmpty)
    }

    func testDeleteAndClearCompleted() throws {
        let store = makeStore()
        let a = try XCTUnwrap(store.add("a"))
        let b = try XCTUnwrap(store.add("b"))
        let c = try XCTUnwrap(store.add("c"))
        store.delete(a.id)
        store.toggle(b.id)
        store.clearCompleted()
        XCTAssertEqual(store.items.map(\.id), [c.id])
    }

    func testPersistsAcrossInstances() throws {
        let file = tempFile()
        let first = makeStore(file: file)
        let done = try XCTUnwrap(first.add("done"))
        first.add("open")
        first.toggle(done.id)

        let second = makeStore(file: file)
        XCTAssertEqual(second.openItems.map(\.title), ["open"])
        XCTAssertEqual(second.completedItems.map(\.title), ["done"])
    }

    func testNewDayDropsYesterdaysCompletedButKeepsOpenItems() throws {
        let file = tempFile()
        let store = makeStore(file: file)
        let done = try XCTUnwrap(store.add("昨天完成的"))
        store.add("还没做的")
        store.toggle(done.id)

        clock = clock.addingTimeInterval(24 * 3600)
        store.rollOverIfNeeded()
        XCTAssertEqual(store.openItems.map(\.title), ["还没做的"])
        XCTAssertTrue(store.completedItems.isEmpty)

        // Also applied on launch.
        let reloaded = makeStore(file: file)
        XCTAssertEqual(reloaded.items.map(\.title), ["还没做的"])
    }

    func testCompletedTodayIsKeptAfterRollOverCheck() throws {
        let store = makeStore()
        let item = try XCTUnwrap(store.add("今天完成"))
        store.toggle(item.id)
        clock = clock.addingTimeInterval(60)
        store.rollOverIfNeeded()
        XCTAssertEqual(store.completedItems.count, 1)
    }

    func testCorruptFileIsBackedUpNotOverwritten() throws {
        let file = tempFile()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)

        let store = makeStore(file: file)
        XCTAssertTrue(store.items.isEmpty)
        let backup = file.appendingPathExtension("corrupt")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "not json")
    }
}
