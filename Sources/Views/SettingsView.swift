import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.panelActions) private var actions
    @State private var launchAtLogin = false

    private let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]

    var body: some View {
        @Bindable var settings = settings
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                group("行为") {
                    row("常驻显示") {
                        Toggle("常驻显示", isOn: $settings.isPinned)
                            .accessibilityIdentifier("settings.pinned")
                    }
                    row("开机自动启动") {
                        Toggle("开机自动启动", isOn: Binding(
                            get: { launchAtLogin },
                            set: { actions.setLaunchAtLogin($0); launchAtLogin = actions.launchAtLogin() }
                        ))
                        .accessibilityIdentifier("settings.launchAtLogin")
                    }
                    row("边缘触发延迟") {
                        Picker("边缘触发延迟", selection: $settings.triggerDelay) {
                            ForEach(AppSettings.TriggerDelay.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("settings.triggerDelay")
                    }
                }
                .toggleStyle(.switch)

                group("市场指数") {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                        ForEach(MarketIndex.catalog) { index in
                            Toggle(index.name, isOn: Binding(
                                get: { settings.enabledIndices.contains(index.code) },
                                set: { settings.setIndex(index.code, enabled: $0) }
                            ))
                            .accessibilityIdentifier("settings.index.\(index.code)")
                        }
                    }
                    row("涨跌颜色") {
                        Picker("涨跌颜色", selection: $settings.redMeansUp) {
                            Text("红涨绿跌").tag(true)
                            Text("绿涨红跌").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("settings.trendColor")
                    }
                    .padding(.top, 4)
                }
                .toggleStyle(.checkbox)

                group("赛事") {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                        ForEach(League.catalog) { league in
                            Toggle(league.name, isOn: Binding(
                                get: { settings.enabledLeagues.contains(league.path) },
                                set: { settings.setLeague(league.path, enabled: $0) }
                            ))
                            .accessibilityIdentifier("settings.league.\(league.path)")
                        }
                    }
                }
                .toggleStyle(.checkbox)

                VStack(alignment: .leading, spacing: 6) {
                    Text("⌥⌘T 呼出 / 收起 · 鼠标移到屏幕最右侧自动弹出")
                    Text("行情来自腾讯财经，赛事来自 ESPN，仅供参考")
                    HStack {
                        Text("tat \(Self.version)")
                        Spacer()
                        Button("退出 tat") { actions.quit() }
                            .controlSize(.small)
                            .accessibilityIdentifier("settings.quit")
                    }
                    .padding(.top, 4)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            .padding(Theme.padding)
        }
        .scrollIndicators(.never)
        .onAppear { launchAtLogin = actions.launchAtLogin() }
    }

    /// Label on the left, control on the right.
    private func row(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            control()
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
        }
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: title)
            content()
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
