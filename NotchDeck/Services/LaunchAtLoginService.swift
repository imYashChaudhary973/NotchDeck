import Foundation
import Observation
import ServiceManagement

/// Registers NotchDeck as a login item via `SMAppService`.
///
/// The system is the source of truth (users can change login items in System Settings),
/// so status is read back from `SMAppService` rather than stored in preferences.
@MainActor
@Observable
final class LaunchAtLoginService {
    enum Status: Equatable {
        case enabled
        case disabled
        /// Registered, but the user must approve it in System Settings ▸ General ▸ Login Items.
        case requiresApproval
        case unavailable
    }

    private(set) var status: Status = .disabled
    private(set) var lastError: String?

    init() {
        refresh()
    }

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    func refresh() {
        status = switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .disabled
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
