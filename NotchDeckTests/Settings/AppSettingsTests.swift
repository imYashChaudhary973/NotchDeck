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

    @Test func featuresAreOnByDefaultAndScrollVolumeIsOff() {
        let settings = AppSettings(defaults: defaults)

        #expect(Feature.allCases.allSatisfy(settings.isEnabled))
        #expect(!settings.scrollAdjustsVolume)
        #expect(settings.timerPlaysSound)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func featureTogglesPersist() {
        let settings = AppSettings(defaults: defaults)
        settings.systemMetricsEnabled = false
        settings.scrollAdjustsVolume = true

        let reloaded = AppSettings(defaults: defaults)

        #expect(!reloaded.isEnabled(.systemMetrics))
        #expect(reloaded.isEnabled(.timers))
        #expect(reloaded.scrollAdjustsVolume)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func stringValuesFromLaunchArgumentsAreAccepted() {
        defaults.set("NO", forKey: AppSettings.Key.audioEnabled)
        defaults.set("YES", forKey: AppSettings.Key.scrollAdjustsVolume)

        let settings = AppSettings(defaults: defaults)

        #expect(!settings.audioEnabled)
        #expect(settings.scrollAdjustsVolume)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
