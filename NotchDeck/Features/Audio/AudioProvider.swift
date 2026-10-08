import Foundation

/// Output volume, mute and output device in the command center, plus optional
/// scroll-over-the-notch volume adjustment with a brief volume HUD.
///
/// Event-driven: CoreAudio property listeners report changes (including ones made with the
/// keyboard or in Control Center); nothing polls.
@MainActor
final class AudioProvider: ActivityProvider {
    let source = ActivitySource(rawValue: "audio")
    static let activityID = "volume"
    /// One scroll step (a mouse-wheel notch) changes the volume by this much, like the volume keys.
    static let scrollStep = 1.0 / 16
    static let hudDuration: Duration = .milliseconds(1500)

    enum ActionID {
        static let setVolume = "setVolume"
        static let toggleMute = "toggleMute"
        static let outputPrefix = "output-"
    }

    private(set) var snapshot = AudioOutputSnapshot()
    /// Whether the volume HUD is showing (after a scroll over the notch).
    private(set) var isShowingHUD = false

    private var publisher: ActivityPublisher?
    private let output: any AudioOutputControlling
    private let scrollAdjustsVolume: () -> Bool
    private var hudTask: Task<Void, Never>?

    init(output: any AudioOutputControlling = CoreAudioOutput(), scrollAdjustsVolume: @escaping () -> Bool = { false }) {
        self.output = output
        self.scrollAdjustsVolume = scrollAdjustsVolume
    }

    // MARK: ActivityProvider

    func start(publisher: ActivityPublisher) {
        self.publisher = publisher
        output.startObserving { [weak self] in self?.refresh() }
        refresh()
    }

    func stop() {
        output.stopObserving()
        hudTask?.cancel()
        hudTask = nil
        isShowingHUD = false
        publisher = nil
    }

    func perform(actionID: ActivityAction.ID, on activityID: NotchActivity.ID) {
        if actionID == ActionID.toggleMute, let muted = snapshot.isMuted {
            output.setMuted(!muted)
            refresh()
        } else if actionID.hasPrefix(ActionID.outputPrefix),
                  let id = UInt32(actionID.dropFirst(ActionID.outputPrefix.count)) {
            output.setDefaultDevice(id)
            refresh()
        }
    }

    func adjust(actionID: ActivityAction.ID, to value: Double, on activityID: NotchActivity.ID) {
        guard actionID == ActionID.setVolume, snapshot.volume != nil else { return }
        output.setVolume(value)
        refresh()
    }

    func handleNotchScroll(_ delta: Double) -> Bool {
        guard scrollAdjustsVolume(), let volume = snapshot.volume else { return false }
        let target = min(max(volume + delta * Self.scrollStep, 0), 1)
        if target != volume || snapshot.isMuted == true {
            output.setVolume(target)
        }
        showHUD()
        refresh()
        return true
    }

    // MARK: State

    func refresh() {
        snapshot = output.snapshot()
        guard let publisher else { return }
        if let activity = Self.activity(for: snapshot, showsHUD: isShowingHUD, source: source) {
            publisher.publish(activity)
        } else {
            publisher.withdraw(id: Self.activityID)
        }
    }

    private func showHUD() {
        isShowingHUD = true
        hudTask?.cancel()
        hudTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hudDuration)
            guard !Task.isCancelled else { return }
            self?.hideHUD()
        }
    }

    /// Returns the volume to the command center. Called when the HUD times out, or directly in tests.
    func hideHUD() {
        hudTask?.cancel()
        hudTask = nil
        guard isShowingHUD else { return }
        isShowingHUD = false
        refresh()
    }

    // MARK: Activity

    static func symbolName(volume: Double?, isMuted: Bool?) -> String {
        guard let volume else { return "speaker.fill" }
        if isMuted == true || volume == 0 { return "speaker.slash.fill" }
        return switch volume {
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    /// The volume activity, or nil when there is no output device.
    /// - Parameter showsHUD: Publish as a notch HUD that reveals on every change (after a scroll).
    static func activity(for snapshot: AudioOutputSnapshot, showsHUD: Bool, source: ActivitySource) -> NotchActivity? {
        guard let device = snapshot.defaultDevice else { return nil }
        let muted = snapshot.isMuted == true
        let valueText: String = if let volume = snapshot.volume {
            muted ? "Muted" : volume.formatted(.percent.precision(.fractionLength(0)))
        } else {
            "Fixed"
        }

        return NotchActivity(
            id: activityID,
            source: source,
            kind: .system,
            // In the command center, above the CPU/memory/battery rows (priority only orders the list there).
            // The HUD answers the user's own scroll, so it outranks running timers and transfers.
            priority: showsHUD ? .timeSensitive : ActivityPriority(rawValue: 14),
            placement: showsHUD ? .notch : .commandCenter,
            title: "Volume",
            subtitle: snapshot.volume == nil ? "\(device.name) · volume can't be changed here" : device.name,
            presentation: ActivityPresentation(
                symbolName: symbolName(volume: snapshot.volume, isMuted: snapshot.isMuted),
                accent: .orange,
                compactAccessory: .text(valueText),
                content: .level(LevelContent(
                    value: snapshot.volume ?? 1,
                    valueText: valueText,
                    adjustActionID: snapshot.volume == nil ? nil : ActionID.setVolume,
                    muteActionID: snapshot.isMuted == nil ? nil : ActionID.toggleMute,
                    isMuted: muted
                )),
                revealsOnUpdate: showsHUD,
                options: ActivityOptions(title: "Output", options: snapshot.devices.map { candidate in
                    ActivityOptions.Option(
                        actionID: ActionID.outputPrefix + String(candidate.id),
                        title: candidate.name,
                        symbolName: candidate.transport.symbolName,
                        isSelected: candidate.id == device.id
                    )
                })
            )
        )
    }
}
