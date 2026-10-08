import Foundation
import IOKit.pwr_mgt

/// Holds or releases a "keep the Mac awake" power assertion.
@MainActor
protocol PowerAssertionControlling: AnyObject {
    var isHeld: Bool { get }
    /// Holds the assertion, replacing any held one. With a timeout, the system releases it by
    /// itself at that point even if NotchDeck doesn't (a safety net, not the primary mechanism).
    @discardableResult
    func acquire(reason: String, timeout: TimeInterval?) -> Bool
    func release()
}

/// An IOKit power assertion that prevents idle display sleep (and with it, idle system sleep) —
/// the supported mechanism behind `caffeinate -d`. Assertions die with the process, so a crash
/// can never leave the Mac awake.
@MainActor
final class IOKitPowerAssertion: PowerAssertionControlling {
    private var assertionID: IOPMAssertionID?

    var isHeld: Bool { assertionID != nil }

    @discardableResult
    func acquire(reason: String, timeout: TimeInterval?) -> Bool {
        release()
        var properties: [String: Any] = [
            kIOPMAssertionTypeKey: kIOPMAssertPreventUserIdleDisplaySleep,
            kIOPMAssertionLevelKey: IOPMAssertionLevel(kIOPMAssertionLevelOn),
            kIOPMAssertionNameKey: reason,
        ]
        if let timeout, timeout > 0 {
            properties[kIOPMAssertionTimeoutKey] = timeout
            properties[kIOPMAssertionTimeoutActionKey] = kIOPMAssertionTimeoutActionRelease
        }
        var id = IOPMAssertionID(0)
        guard IOPMAssertionCreateWithProperties(properties as CFDictionary, &id) == kIOReturnSuccess else {
            return false
        }
        assertionID = id
        return true
    }

    func release() {
        guard let assertionID else { return }
        IOPMAssertionRelease(assertionID)
        self.assertionID = nil
    }
}
