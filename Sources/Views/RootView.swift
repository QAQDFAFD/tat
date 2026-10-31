import SwiftUI

struct RootView: View {
    @Environment(TipsStore.self) private var tips
    @Environment(AppSettings.self) private var settings
    @Environment(PanelUIState.self) private var ui
    @Environment(\.panelActions) private var actions

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider().opacity(0.6)
            if ui.showingSettings {
                SettingsView()
                    .transition(.opacity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        TodoSection()
                        if !settings.enabledIndices.isEmpty {
                            MarketSection()
                        }
                        if !settings.enabledLeagues.isEmpty {
                            MatchSection()
                        }
                    }
                    .padding(.horizontal, Theme.padding - 6)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.never)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(Theme.accent)
        .animation(.easeOut(duration: 0.15), value: ui.showingSettings)
        .onExitCommand { actions.dismiss() }
        .onChange(of: settings.enabledIndices) { tips.refresh() }
        .onChange(of: settings.enabledLeagues) { tips.refresh() }
    }
}

struct HeaderView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PanelUIState.self) private var ui

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            TimelineView(.everyMinute) { context in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Self.day.string(from: context.date))
                        .font(.system(size: 15, weight: .semibold))
                    Text(Self.weekday.string(from: context.date))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("header.date")
            }
            Spacer()
            IconButton(
                symbol: settings.isPinned ? "pin.fill" : "pin",
                label: settings.isPinned ? "取消常驻" : "常驻显示",
                identifier: "header.pin",
                isActive: settings.isPinned
            ) {
                settings.isPinned.toggle()
            }
            IconButton(
                symbol: ui.showingSettings ? "xmark" : "gearshape",
                label: ui.showingSettings ? "关闭设置" : "设置",
                identifier: "header.settings"
            ) {
                ui.showingSettings.toggle()
            }
        }
        .padding(.leading, Theme.padding)
        .padding(.trailing, Theme.padding - 6)
        .padding(.vertical, 10)
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}
