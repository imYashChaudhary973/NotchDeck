import CoreGraphics
import Testing
@testable import NotchDeck

struct CompactLayoutTests {
    @Test func compactAccessoryStaysClearOfTheNotch() {
        let used = NotchLayout.compactContentInset + NotchLayout.compactAccessoryMaxWidth + NotchLayout.compactNotchGap
        #expect(used == NotchLayout.compactEarWidth)
        #expect(NotchLayout.compactGlyphSize <= NotchLayout.compactAccessoryMaxWidth)
        #expect(NotchLayout.compactArtworkSize <= NotchLayout.compactAccessoryMaxWidth)
        // Fits the shortest notch (32 pt on 14-inch MacBook Pros) with room to spare.
        #expect(NotchLayout.compactArtworkSize <= 24)
    }

    @Test func liveActivityAddsBothEarsToTheNotch() {
        let metrics = NotchLayout.metrics(for: .liveActivity, notchSize: CGSize(width: 220, height: 38))
        #expect(metrics.bodySize == CGSize(width: 220 + NotchLayout.compactEarWidth * 2, height: 38))
    }

    @Test func peekSideContentFitsBesideTheNotch() {
        let notch = CGSize(width: 220, height: 38)
        let side = NotchLayout.peekSideContentWidth(notchWidth: notch.width)
        let body = NotchLayout.metrics(for: .peek, notchSize: notch).bodySize.width
        #expect(side > 0)
        #expect(16 + side + NotchLayout.compactNotchGap <= (body - notch.width) / 2)
    }

    @Test func peekSideContentIsNeverNegative() {
        #expect(NotchLayout.peekSideContentWidth(notchWidth: 2_000) >= 0)
    }
}

@MainActor
struct NotchPrewarmerTests {
    private func contentStyle(_ content: ActivityContent) -> String {
        switch content {
        case .standard: "standard"
        case .media: "media"
        case .level: "level"
        case .metric: "metric"
        case .toggle: "toggle"
        case .actions: "actions"
        case .schedule: "schedule"
        case .collection: "collection"
        }
    }

    private func accessoryStyle(_ accessory: CompactAccessory?) -> String? {
        switch accessory {
        case .text: "text"
        case .symbol: "symbol"
        case .countdown: "countdown"
        case .progress: "progress"
        case nil: nil
        }
    }

    /// Update these lists (and the samples) when a new presentation style is added.
    @Test func samplesCoverEveryPresentationStyle() {
        let samples = NotchPrewarmer.sampleActivities()
        #expect(Set(samples.map { contentStyle($0.presentation.content) })
            == ["standard", "media", "level", "metric", "toggle", "actions", "schedule", "collection"])
        #expect(Set(samples.compactMap { accessoryStyle($0.presentation.compactAccessory) })
            == ["text", "symbol", "countdown", "progress"])
        #expect(samples.contains { $0.priority.requestsAttention && $0.presentation.statusText != nil })
        #expect(samples.contains { $0.presentation.options != nil })
        // Artwork is drawn as an image, not a symbol, so it has its own first-render cost.
        #expect(samples.contains { if case .media(let media) = $0.presentation.content { media.artwork != nil } else { false } })
    }

    @Test func samplesUseAPrivateSourceAndUniqueIDs() {
        let samples = NotchPrewarmer.sampleActivities()
        #expect(Set(samples.map(\.id)).count == samples.count)
        #expect(Set(samples.map(\.source)) == [ActivitySource(rawValue: "prewarm")])
    }
}
