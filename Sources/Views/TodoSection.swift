import SwiftUI

struct TodoSection: View {
    @Environment(TodoStore.self) private var todos
    @Environment(PanelUIState.self) private var ui

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TodoInput()
                .padding(.bottom, 6)

            ForEach(todos.openItems) { item in
                TodoRow(item: item)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            }

            if todos.openItems.isEmpty {
                Text(todos.completedItems.isEmpty ? "今天还没有待办" : "全部完成，干得漂亮")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("todo.empty")
            }

            if !todos.completedItems.isEmpty {
                CompletedHeader(count: todos.completedItems.count)
                    .padding(.top, 4)
                if ui.completedExpanded {
                    ForEach(todos.completedItems) { item in
                        TodoRow(item: item)
                            .transition(.opacity)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: todos.items)
        .animation(.easeOut(duration: 0.2), value: ui.completedExpanded)
    }
}

private struct TodoInput: View {
    @Environment(TodoStore.self) private var todos
    @Environment(PanelUIState.self) private var ui
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var ui = ui
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(focused ? Theme.accent : .secondary)
                .frame(width: 18)
            TextField("添加待办，回车确认", text: $ui.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit(submit)
                .accessibilityIdentifier("todo.input")
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.accent.opacity(focused ? 0.7 : 0), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: focused)
        .onChange(of: ui.focusRequest) { focused = true }
        .onAppear { if ui.focusRequest > 0 { focused = true } }
    }

    private func submit() {
        if todos.add(ui.draft) != nil {
            ui.draft = ""
        }
        focused = true
    }
}

struct TodoRow: View {
    let item: TodoItem

    @Environment(TodoStore.self) private var todos
    @State private var hovering = false
    /// Shows the check mark for a moment before the item moves to "已完成".
    @State private var completing = false

    private var showsDone: Bool { item.isDone || completing }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: toggle) {
                Image(systemName: showsDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(showsDone ? Theme.accent : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            .accessibilityLabel(item.isDone ? "标记未完成：\(item.title)" : "完成：\(item.title)")
            .accessibilityIdentifier("todo.toggle")

            Text(item.title)
                .font(.system(size: 13))
                .strikethrough(showsDone, color: .secondary)
                .foregroundStyle(showsDone ? .secondary : .primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("todo.title")

            Button {
                withAnimation(.easeOut(duration: 0.2)) { todos.delete(item.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .help("删除")
            .accessibilityLabel("删除：\(item.title)")
            .accessibilityIdentifier("todo.delete")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Theme.rowCorner).fill(Color.primary.opacity(hovering ? 0.05 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button(item.isDone ? "标记为未完成" : "完成", action: toggle)
            Button("删除", role: .destructive) { todos.delete(item.id) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(item.isDone ? "todo.doneRow" : "todo.row")
    }

    private func toggle() {
        guard !item.isDone else {
            withAnimation(.easeOut(duration: 0.2)) { todos.toggle(item.id) }
            return
        }
        guard !completing else { return }
        withAnimation(.easeOut(duration: 0.15)) { completing = true }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeOut(duration: 0.2)) { todos.toggle(item.id) }
            completing = false
        }
    }
}

private struct CompletedHeader: View {
    let count: Int

    @Environment(TodoStore.self) private var todos
    @Environment(PanelUIState.self) private var ui

    var body: some View {
        HStack(spacing: 6) {
            Button {
                ui.completedExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(ui.completedExpanded ? 90 : 0))
                    Text("已完成 \(count)")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ui.completedExpanded ? "收起已完成，共 \(count) 项" : "展开已完成，共 \(count) 项")
            .accessibilityIdentifier("todo.completedToggle")

            Spacer()

            Button("清除") {
                withAnimation(.easeOut(duration: 0.2)) { todos.clearCompleted() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .help("清除今天已完成的待办")
            .accessibilityIdentifier("todo.clearCompleted")
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
    }
}
