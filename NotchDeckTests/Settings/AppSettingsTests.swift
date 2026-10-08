import Foundation
import Testing
@testable import NotchDeck

@MainActor
struct AppSettingsTests {
    let suiteName = "NotchDeckTests.AppSettings.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    @Test func defaultsAreApplied() {
        let settings = AppSettings(defaults: defaults)

        #expect(settings.peeksOnHover)
        #expect(settings.collapsesWhenPointerExits)
        #expect(settings.peeksForAttention)
        #expect(settings.displayPreference == .automatic)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func changesPersistAcrossInstances() {
        let settings = AppSettings(defaults: defaults)
        settings.peeksOnHover = false
        settings.displayPreference = .primary

        let reloaded = AppSettings(defaults: defaults)

        #expect(!reloaded.peeksOnHover)
        #expect(reloaded.displayPreference == .primary)
        #expect(reloaded.stateMachineConfiguration.peeksOnHover == false)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func unknownStoredDisplayPreferenceFallsBackToAutomatic() {
        defaults.set("someFutureValue", forKey: AppSettings.Key.displayPreference)
        #expect(AppSettings(defaults: defaults).displayPreference == .automatic)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
