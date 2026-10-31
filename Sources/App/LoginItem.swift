import Foundation
import ServiceManagement

/// "Open at login" through `SMAppService` (macOS 13+). Disabled in UI tests so a test
/// run never changes the user's login items.
@MainActor
final class LoginItem {
    private let isAvailable: Bool

    init(isAvailable: Bool) {
        self.isAvailable = isAvailable
    }

    var isEnabled: Bool {
        get {
            guard isAvailable else { return false }
            return SMAppService.mainApp.status == .enabled
        }
        set {
            guard isAvailable else { return }
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("tat: failed to update login item: \(error)")
            }
        }
    }
}
