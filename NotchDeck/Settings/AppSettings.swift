import Foundation
import Observation

/// A feature that can be turned off in Settings.
enum Feature: CaseIterable, Sendable {
    case timers
    case keepAwake
    case systemMetrics
    case audio
    case quickActions

    var title: String {
        switch self {
        case .timers: "Timers"
        case .keepAwake: "Keep Awake"
        case .systemMetrics: "System metrics"
        case .audio: "Audio controls"
        case .quickActions: "Quick actions"
        }
    }
}

/// User preferences, persisted in `UserDefaults`.
///
/// Add new settings as stored properties that write through in `didSet`, with a key in `Key`
/// and a default in `init`. Views and controllers observe this object via Observation.
@MainActor
@Observable
final class AppSettings {
    enum Key {
        static let peeksOnHover = "notch.peeksOnHover"
        static let collapsesWhenPointerExits = "notch.collapsesWhenPointerExits"
        static let peeksForAttention = "notch.peeksForAttention"
        static let displayPreference = "notch.displayPreference"
        static let timersEnabled = "features.timers.enabled"
        static let keepAwakeEnabled = "features.keepAwake.enabled"
        static let systemMetricsEnabled = "features.systemMetrics.enabled"
        static let audioEnabled = "features.audio.enabled"
        static let quickActionsEnabled = "features.quickActions.enabled"
        static let scrollAdjustsVolume = "audio.scrollAdjustsVolume"
        static let timerPlaysSound = "timers.playsSound"
    }

    var peeksOnHover: Bool {
        didSet { defaults.set(peeksOnHover, forKey: Key.peeksOnHover) }
    }

    var collapsesWhenPointerExits: Bool {
        didSet { defaults.set(collapsesWhenPointerExits, forKey: Key.collapsesWhenPointerExits) }
    }

    var peeksForAttention: Bool {
        didSet { defaults.set(peeksForAttention, forKey: Key.peeksForAttention) }
    }

    var displayPreference: DisplayPreference {
        didSet { defaults.set(displayPreference.rawValue, forKey: Key.displayPreference) }
    }

    // MARK: Features

    var timersEnabled: Bool {
        didSet { defaults.set(timersEnabled, forKey: Key.timersEnabled) }
    }

    var keepAwakeEnabled: Bool {
        didSet { defaults.set(keepAwakeEnabled, forKey: Key.keepAwakeEnabled) }
    }

    var systemMetricsEnabled: Bool {
        didSet { defaults.set(systemMetricsEnabled, forKey: Key.systemMetricsEnabled) }
    }

    var audioEnabled: Bool {
        didSet { defaults.set(audioEnabled, forKey: Key.audioEnabled) }
    }

    var quickActionsEnabled: Bool {
        didSet { defaults.set(quickActionsEnabled, forKey: Key.quickActionsEnabled) }
    }

    /// Scrolling over the notch changes the output volume. Off by default: it is easy to trigger by accident.
    var scrollAdjustsVolume: Bool {
        didSet { defaults.set(scrollAdjustsVolume, forKey: Key.scrollAdjustsVolume) }
    }

    var timerPlaysSound: Bool {
        didSet { defaults.set(timerPlaysSound, forKey: Key.timerPlaysSound) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        peeksOnHover = Self.bool(Key.peeksOnHover, in: defaults, default: true)
        collapsesWhenPointerExits = Self.bool(Key.collapsesWhenPointerExits, in: defaults, default: true)
        peeksForAttention = Self.bool(Key.peeksForAttention, in: defaults, default: true)
        displayPreference = defaults.string(forKey: Key.displayPreference)
            .flatMap(DisplayPreference.init(rawValue:)) ?? .automatic
        timersEnabled = Self.bool(Key.timersEnabled, in: defaults, default: true)
        keepAwakeEnabled = Self.bool(Key.keepAwakeEnabled, in: defaults, default: true)
        systemMetricsEnabled = Self.bool(Key.systemMetricsEnabled, in: defaults, default: true)
        audioEnabled = Self.bool(Key.audioEnabled, in: defaults, default: true)
        quickActionsEnabled = Self.bool(Key.quickActionsEnabled, in: defaults, default: true)
        scrollAdjustsVolume = Self.bool(Key.scrollAdjustsVolume, in: defaults, default: false)
        timerPlaysSound = Self.bool(Key.timerPlaysSound, in: defaults, default: true)
    }

    /// Reads a stored Bool, accepting launch-argument strings such as `-features.audio.enabled NO`.
    private static func bool(_ key: String, in defaults: UserDefaults, default defaultValue: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
    }

    func isEnabled(_ feature: Feature) -> Bool {
        switch feature {
        case .timers: timersEnabled
        case .keepAwake: keepAwakeEnabled
        case .systemMetrics: systemMetricsEnabled
        case .audio: audioEnabled
        case .quickActions: quickActionsEnabled
        }
    }

    /// The subset of settings the notch state machine depends on.
    var stateMachineConfiguration: NotchStateMachine.Configuration {
        NotchStateMachine.Configuration(
            peeksOnHover: peeksOnHover,
            collapsesWhenPointerExits: collapsesWhenPointerExits,
            peeksForAttention: peeksForAttention
        )
    }
}
