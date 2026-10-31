import Foundation
import Observation

struct TodoItem: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var createdAt: Date
    var completedAt: Date?

    var isDone: Bool { completedAt != nil }
}

/// Holds the todo list and persists it as JSON.
///
/// Rules (see docs/DESIGN.md §3.1):
/// - open items carry over across days;
/// - items completed before today are dropped, so the list is always "today".
@MainActor
@Observable
final class TodoStore {
    static let maxTitleLength = 200

    private(set) var items: [TodoItem] = []

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar

    init(fileURL: URL?, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.now = now
        self.calendar = calendar
        load()
        rollOverIfNeeded()
    }

    /// Open items, newest first. `items` is append-only in creation order, so reversing it
    /// gives a stable order even when two items share the same (second-precision) timestamp.
    var openItems: [TodoItem] {
        items.filter { !$0.isDone }.reversed()
    }

    /// Items completed today, most recently completed first.
    var completedItems: [TodoItem] {
        items.filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    @discardableResult
    func add(_ rawTitle: String) -> TodoItem? {
        let title = String(rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxTitleLength))
        guard !title.isEmpty else { return nil }
        let item = TodoItem(id: UUID(), title: title, createdAt: now(), completedAt: nil)
        items.append(item)
        save()
        return item
    }

    func toggle(_ id: TodoItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].completedAt = items[index].isDone ? nil : now()
        save()
    }

    func delete(_ id: TodoItem.ID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clearCompleted() {
        items.removeAll(where: \.isDone)
        save()
    }

    /// Drops items completed before the start of today. Call on launch and when the day changes.
    func rollOverIfNeeded() {
        let startOfToday = calendar.startOfDay(for: now())
        let before = items.count
        items.removeAll { item in
            guard let completedAt = item.completedAt else { return false }
            return completedAt < startOfToday
        }
        if items.count != before { save() }
    }

    // MARK: - Persistence

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        do {
            items = try Self.decoder.decode([TodoItem].self, from: data)
        } catch {
            // Keep the unreadable file around instead of silently overwriting the user's list.
            let backup = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            items = []
        }
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try Self.encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("tat: failed to save todos: \(error)")
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
}
