import AppKit
import SwiftUI
import XCTest
@testable import Tat

@MainActor
final class PanelControllerTests: XCTestCase {
    func testEveryShowRefetchesTips() async throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "needs a display")
        let settings = AppSettings(defaults: UserDefaults(suiteName: "tat.tests.\(UUID().uuidString)")!)
        let tips = TipsStore(settings: settings, marketProvider: StubMarketProvider(), matchProvider: StubMatchProvider())
        let panel = PanelController(rootView: EmptyView(), settings: settings, tips: tips, ui: PanelUIState())
        defer { panel.hide() }

        panel.show(on: nil, viaHover: false, focusInput: false)
        XCTAssertTrue(tips.isLoading, "first show fetches")
        await waitUntilLoaded(tips)
        XCTAssertFalse(tips.isLoading)

        panel.hide()
        panel.show(on: nil, viaHover: false, focusInput: false)
        XCTAssertTrue(tips.isLoading, "showing again right away still fetches, no staleness window")
        await waitUntilLoaded(tips)
    }

    private func waitUntilLoaded(_ store: TipsStore) async {
        for _ in 0..<200 where store.isLoading {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
