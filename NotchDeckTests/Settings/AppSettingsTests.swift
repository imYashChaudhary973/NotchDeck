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

    @Test func featuresAreOnByDefaultExceptCalendarAndScrollVolume() {
        let settings = AppSettings(defaults: defaults)

        // Calendar needs a permission, which is asked for only when the user turns it on.
        #expect(!settings.isEnabled(.calendar))
        #expect(Feature.allCases.filter { $0 != .calendar }.allSatisfy(settings.isEnabled))
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

    @Test func calendarOptionsHaveDefaultsAndPersist() {
        let settings = AppSettings(defaults: defaults)
        #expect(settings.calendarLookAheadHours == 12)
        #expect(settings.calendarNotchLeadMinutes == 15)
        #expect(settings.calendarExcludedIDs.isEmpty)
        #expect(settings.calendarConfiguration.rules == CalendarRules(notchLeadTime: 15 * 60))

        settings.calendarLookAheadHours = 6
        settings.calendarNotchLeadMinutes = 30
        settings.calendarExcludedIDs = ["work", "holidays"]
        let reloaded = AppSettings(defaults: defaults)

        #expect(reloaded.calendarConfiguration.lookAhead == 6 * 3600)
        #expect(reloaded.calendarConfiguration.rules.notchLeadTime == 30 * 60)
        #expect(reloaded.calendarConfiguration.excludedCalendarIDs == ["work", "holidays"])
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func unknownCalendarOptionsFallBackToDefaults() {
        defaults.set(7, forKey: AppSettings.Key.calendarLookAheadHours)
        defaults.set(-1, forKey: AppSettings.Key.calendarNotchLeadMinutes)

        let settings = AppSettings(defaults: defaults)

        #expect(settings.calendarLookAheadHours == 12)
        #expect(settings.calendarNotchLeadMinutes == 15)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
