# 0005. Local Utility Providers: Command-Center Activities, Display Feedback and Input Routing

- Status: Accepted
- Date: 2026-10-08

## Context

Phase 2 adds the first real features: Timers, Keep Awake, System Metrics, Audio and Quick Actions. Three needs did not fit the Phase 1 engine:

1. **Controls and background context.** CPU usage, the volume control, the Keep Awake switch and the Quick Actions grid belong in the command center. As ordinary activities, the lowest of them would become primary whenever nothing else was happening, so the notch would never be idle (the plan's "Idle: the notch looks like a notch").
2. **Energy.** "Metrics sampling is efficient and pauses when not visible." The provider samples, but only the notch layer knows what is on screen. Providers must not depend on the notch UI.
3. **Continuous input.** A volume bar needs a value, not just an action ID. Scrolling over the notch should change the volume, and the controller must not know about audio.

## Decision

- **Placement.** `NotchActivity.placement` is `.notch` (default, Phase 1 behavior) or `.commandCenter`. The resolver picks the primary only from `.notch` activities; `.commandCenter` activities are always queued. They are listed in the expanded command center and never take or hold the notch. For them, priority only orders the list (e.g. Quick Actions 20, volume 14, CPU 13, memory 12, battery 11). An activity can move between placements: Keep Awake is `.commandCenter` while off and a `.notch` Live Activity while on. The volume row becomes a `.notch` HUD for 1.5 s after a scroll.
- **Display feedback.** `NotchDisplay.displayedKeys(state:resolution:selectedSection:)` (pure, unit tested) derives what is on screen: the primary in Live Activity and Peek; the featured card plus visible widgets in the expanded command center; nothing when idle or in the Shelf. `NotchController` reports it to `ActivityEngine.updateDisplayedActivities(_:)`. The engine tells each provider whose share changed through `ActivityProvider.displayedActivitiesChanged(_:)`. Information flows from the notch to the providers; providers still only publish.
- **Input routing.** `ActivityProvider.adjust(actionID:to:on:)` carries a `0…1` value for continuous controls (`LevelContent.adjustActionID`). `ActivityProvider.handleNotchScroll(_:)` receives scrolls over the notch in normalized steps (`NotchScroll`); the engine offers them to providers in registration order and the first that returns `true` wins. Both have default no-op implementations.
- **New presentation data.** `ActivityContent.actions(ActionsContent)` — a tile grid on the featured card, a button row in the widget column (quick actions, timer presets). `ActivityPresentation.options` — a selectable list (output devices). `LevelContent` gains `adjustActionID`, `muteActionID` and `isMuted`. The notch still owns every view.
- **System access behind protocols.** Each feature reads the system through a small protocol (`PowerAssertionControlling`, `SystemStatisticsReading`, `PowerSourceMonitoring`, `AudioOutputControlling`, `WorkspaceOpening`). The real implementations use public IOKit, Mach, sysctl, CoreAudio and NSWorkspace APIs, and tests use fakes.
- **Feature toggles.** `AppEnvironment` registers each Phase 2 provider only while its Settings toggle is on. Turning a feature off unregisters it. Timers are cancelled and Keep Awake is turned off, so the feature does nothing at all. Quitting only unregisters: saved timers and an active Keep Awake session come back on the next launch.

## Alternatives Considered

- **A separate dashboard model beside the engine.** It would duplicate ordering, tabs and action routing, and features would publish into two places.
- **A very low priority for background items.** Something always outranks "nothing", so the notch would never be idle.
- **Providers sampling all the time.** Simple, but it wakes the CPU every couple of seconds all day for numbers nobody is looking at.
- **Giving providers a reference to the notch's visibility.** It couples features to the presentation layer and breaks the core rule.
- **Encoding values in action IDs (`"setVolume:0.42"`).** Stringly typed, and every provider would need its own parsing.

## Consequences

- Idle cost is unchanged: with every Phase 2 feature on and nothing running, NotchDeck measured 0.0% CPU and 0 idle wake-ups (`top`, 5 s samples).
- CPU and memory are sampled every 2 s (500 ms tolerance) only while one of their rows is visible. Battery uses IOKit power-source notifications, memory pressure a dispatch source, and audio CoreAudio property listeners. Nothing polls.
- A visible countdown (`Text(timerInterval:)`, from Phase 1) makes SwiftUI lay out the hosting view once a second: about 1% CPU on an M5 while a timer is on the notch, about 1.5% with the command center open and sampling. Possible later optimization: show minutes only while more than a minute remains.
- New content data (`actions`, `options`, level controls) must be added to the warm-up samples. `NotchPrewarmerTests` enforces this.
