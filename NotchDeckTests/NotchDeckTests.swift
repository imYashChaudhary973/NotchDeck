import Testing
@testable import NotchDeck

/// Smoke test confirming the test bundle builds and links against the app module.
/// Replace with real coverage as Phase 1 introduces testable logic.
struct NotchDeckTests {
    @Test func appModuleIsTestable() {
        #expect(String(describing: NotchDeckApp.self) == "NotchDeckApp")
    }
}
