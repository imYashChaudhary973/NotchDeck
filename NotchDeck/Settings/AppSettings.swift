import Foundation
import Observation

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

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        peeksOnHover = defaults.object(forKey: Key.peeksOnHover) as? Bool ?? true
        collapsesWhenPointerExits = defaults.object(forKey: Key.collapsesWhenPointerExits) as? Bool ?? true
        peeksForAttention = defaults.object(forKey: Key.peeksForAttention) as? Bool ?? true
        displayPreference = defaults.string(forKey: Key.displayPreference)
            .flatMap(DisplayPreference.init(rawValue:)) ?? .automatic
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
