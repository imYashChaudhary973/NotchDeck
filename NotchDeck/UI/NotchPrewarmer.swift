import AppKit
import SwiftUI

/// Draws every notch state once, off-screen, shortly after launch.
///
/// SwiftUI pays a one-time cost (view machinery, fonts, symbols) the first time a view is drawn.
/// Measured on the expanded surface it was ~30 ms — several dropped frames at the start of the
/// first expansion. Drawing sample content off-screen moves that cost to idle time.
///
/// The samples are published to a private `ActivityEngine` that nothing observes; they never
/// reach the real engine or the notch panel.
@MainActor
enum NotchPrewarmer {
    /// Pause between renders so the main thread stays responsive while warming up.
    static let renderSpacing: Duration = .milliseconds(16)

    static func run(geometry: NotchGeometry) async {
        let engine = ActivityEngine(schedulesExpiry: false)
        let model = NotchViewModel(engine: engine)
        let size = NotchLayout.metrics(for: .expanded, notchSize: geometry.notchSize).outerSize
        let view = NSHostingView(rootView: NotchRootView(model: model))
        view.frame = CGRect(
            origin: .zero,
            size: CGSize(width: size.width, height: geometry.notchSize.height + NotchLayout.expandedContentHeightRange.upperBound)
        )

        // Each sample alone (as the featured card, Peek and compact activity), then together so the
        // widget column draws every content style beside both an ordinary and an attention card.
        let samples = sampleActivities()
        let ordinary = samples.filter { !$0.priority.requestsAttention }
        let scenarios = samples.map { [$0] } + [ordinary, samples]
        for scenario in scenarios {
            samples.forEach { engine.withdraw($0.key) }
            scenario.forEach(engine.publish)
            for state in [NotchPresentationState.liveActivity, .peek, .expanded] {
                guard !Task.isCancelled else { return }
                render(view, model: model, state: state, geometry: geometry)
                try? await Task.sleep(for: renderSpacing)
            }
        }
        render(view, model: model, state: .shelf, geometry: geometry)
    }

    private static func render(
        _ view: NSHostingView<NotchRootView>,
        model: NotchViewModel,
        state: NotchPresentationState,
        geometry: NotchGeometry
    ) {
        model.update(state: state, geometry: geometry)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
    }

    /// One activity per content style and compact accessory. Titles cover common letters and
    /// digits so their glyphs are rasterized ahead of time too.
    static func sampleActivities(now: Date = .now) -> [NotchActivity] {
        let source = ActivitySource(rawValue: "prewarm")
        func sample(
            _ id: String,
            _ kind: ActivityKind,
            _ priority: ActivityPriority,
            _ presentation: ActivityPresentation,
            progress: Double? = nil,
            actions: [ActivityAction] = []
        ) -> NotchActivity {
            NotchActivity(
                id: id, source: source, kind: kind, priority: priority,
                title: "The Quick Brown Fox Jumps Over The Lazy Dog",
                subtitle: "the quick brown fox jumps over the lazy dog · 0123456789:%",
                startedAt: now, progress: progress,
                presentation: presentation, actions: actions
            )
        }

        return [
            sample("countdown", .meeting, .timeSensitive, ActivityPresentation(
                symbolName: "calendar", accent: .blue, compactAccessory: .countdown(to: now.addingTimeInterval(60))
            )),
            sample("media", .music, .active, ActivityPresentation(
                symbolName: "music.note", accent: .pink, compactAccessory: .symbol("waveform"),
                content: .media(MediaContent(isPlaying: true, duration: 180, previousActionID: "p", playPauseActionID: "t", nextActionID: "n"))
            )),
            sample("level", .system, .active, ActivityPresentation(
                symbolName: "speaker.wave.2.fill", accent: .orange, compactAccessory: .text("50%"),
                content: .level(LevelContent(value: 0.5, valueText: "50%")), revealsOnUpdate: true
            )),
            sample("metric", .system, .ambient, ActivityPresentation(
                symbolName: "cpu", accent: .green, content: .metric(MetricContent(value: 0.3, valueText: "30%"))
            )),
            sample("toggle", .system, .passive, ActivityPresentation(
                symbolName: "cup.and.saucer.fill", accent: .yellow, compactAccessory: .symbol("bolt.fill"),
                content: .toggle(ToggleContent(isOn: true, actionID: "toggle", stateText: "On"))
            )),
            sample("progress", .fileTransfer, .active, ActivityPresentation(
                symbolName: "arrow.down.circle", accent: .blue, compactAccessory: .progress
            ), progress: 0.4),
            sample("attention", .agent, .attentionRequired, ActivityPresentation(
                symbolName: "sparkle", accent: .orange, compactAccessory: .symbol("exclamationmark"),
                statusText: "Needs approval"
            ), actions: [ActivityAction(id: "approve", title: "Approve"), ActivityAction(id: "deny", title: "Deny", isDestructive: true)]),
        ]
    }
}
