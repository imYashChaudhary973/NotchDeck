import Foundation
@testable import NotchDeck

extension ActivitySource {
    static let testA = ActivitySource(rawValue: "test-a")
    static let testB = ActivitySource(rawValue: "test-b")
}

/// Builds an activity with sensible defaults so tests only state what matters.
func makeActivity(
    _ id: String,
    source: ActivitySource = .testA,
    priority: ActivityPriority = .passive,
    placement: ActivityPlacement = .notch,
    kind: ActivityKind = .generic,
    expiresAt: Date? = nil,
    title: String? = nil
) -> NotchActivity {
    NotchActivity(
        id: id,
        source: source,
        kind: kind,
        priority: priority,
        placement: placement,
        title: title ?? id,
        startedAt: Date(timeIntervalSinceReferenceDate: 0),
        expiresAt: expiresAt,
        presentation: ActivityPresentation(symbolName: "circle")
    )
}

/// A mutable clock for engine tests.
@MainActor
final class TestClock {
    var now = Date(timeIntervalSinceReferenceDate: 1_000)

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}
