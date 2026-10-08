import Foundation

/// How an output device is connected, used to pick its icon.
enum AudioTransport: Equatable, Sendable {
    case builtIn
    case bluetooth
    case usb
    case display
    case airPlay
    case other

    var symbolName: String {
        switch self {
        case .builtIn: "laptopcomputer"
        case .bluetooth: "headphones"
        case .usb: "cable.connector"
        case .display: "display"
        case .airPlay: "airplayaudio"
        case .other: "hifispeaker"
        }
    }
}

struct AudioOutputDevice: Identifiable, Equatable, Sendable {
    /// The CoreAudio object ID (valid for this boot session).
    let id: UInt32
    var name: String
    var transport: AudioTransport
}

/// The audio output as seen at one moment.
struct AudioOutputSnapshot: Equatable, Sendable {
    var devices: [AudioOutputDevice] = []
    var defaultDeviceID: UInt32?
    /// Nil when the default device has no volume control (e.g. some HDMI and digital outputs).
    var volume: Double?
    /// Nil when the default device can't be muted.
    var isMuted: Bool?

    var defaultDevice: AudioOutputDevice? {
        devices.first { $0.id == defaultDeviceID }
    }
}

/// Reads and changes the system audio output.
@MainActor
protocol AudioOutputControlling: AnyObject {
    func snapshot() -> AudioOutputSnapshot
    @discardableResult func setVolume(_ volume: Double) -> Bool
    @discardableResult func setMuted(_ muted: Bool) -> Bool
    @discardableResult func setDefaultDevice(_ id: UInt32) -> Bool
    /// Calls back (on the main actor) when devices, the default device, its volume or mute change.
    func startObserving(onChange: @escaping @MainActor () -> Void)
    func stopObserving()
}
