import AudioToolbox
import CoreAudio
import Foundation

/// Audio output control through the public CoreAudio HAL (`AudioObject…` functions).
///
/// Volume uses the virtual main volume, which works for devices with either a main control or
/// per-channel controls. Devices without a settable volume or mute report `nil`, and the
/// feature shows the control as unavailable. Changes are observed with property listeners on
/// the main queue; nothing polls.
@MainActor
final class CoreAudioOutput: AudioOutputControlling {
    private let system = AudioObjectID(kAudioObjectSystemObject)
    private var onChange: (@MainActor () -> Void)?
    /// Listeners on the system object (device list, default device).
    private var systemListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    /// Listeners on the current default device (volume, mute), re-installed when it changes.
    private var deviceListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    // MARK: Reading

    func snapshot() -> AudioOutputSnapshot {
        let defaultID = defaultOutputDeviceID()
        return AudioOutputSnapshot(
            devices: outputDevices(),
            defaultDeviceID: defaultID,
            volume: defaultID.flatMap(volume(of:)),
            isMuted: defaultID.flatMap(isMuted(_:))
        )
    }

    private func outputDevices() -> [AudioOutputDevice] {
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasOutputStreams(id), !isHidden(id), let name = string(kAudioObjectPropertyName, of: id) else { return nil }
            return AudioOutputDevice(id: id, name: name, transport: transport(of: id))
        }
    }

    private func defaultOutputDeviceID() -> AudioObjectID? {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &id) == noErr, id != kAudioObjectUnknown else { return nil }
        return id
    }

    private func hasOutputStreams(_ id: AudioObjectID) -> Bool {
        var address = Self.address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private func isHidden(_ id: AudioObjectID) -> Bool {
        var address = Self.address(kAudioDevicePropertyIsHidden)
        var hidden: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &hidden) == noErr && hidden != 0
    }

    private func string(_ selector: AudioObjectPropertySelector, of id: AudioObjectID) -> String? {
        var address = Self.address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private func transport(of id: AudioObjectID) -> AudioTransport {
        var address = Self.address(kAudioDevicePropertyTransportType)
        var type: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &type) == noErr else { return .other }
        switch type {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeThunderbolt: return .display
        case kAudioDeviceTransportTypeAirPlay: return .airPlay
        default: return .other
        }
    }

    private static let volumeAddress = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioObjectPropertyScopeOutput)
    private static let muteAddress = address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)

    private func volume(of id: AudioObjectID) -> Double? {
        var address = Self.volumeAddress
        guard AudioObjectHasProperty(id, &address), isSettable(id, address) else { return nil }
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return Double(volume)
    }

    private func isMuted(_ id: AudioObjectID) -> Bool? {
        var address = Self.muteAddress
        guard AudioObjectHasProperty(id, &address), isSettable(id, address) else { return nil }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &muted) == noErr else { return nil }
        return muted != 0
    }

    private func isSettable(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &address, &settable) == noErr && settable.boolValue
    }

    // MARK: Changing

    @discardableResult
    func setVolume(_ volume: Double) -> Bool {
        guard let id = defaultOutputDeviceID() else { return false }
        var address = Self.volumeAddress
        guard AudioObjectHasProperty(id, &address) else { return false }
        var value = Float32(min(max(volume, 0), 1))
        let status = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        // Turning the volume up from zero should be audible, as with the keyboard volume keys.
        if status == noErr, value > 0, isMuted(id) == true {
            setMuted(false)
        }
        return status == noErr
    }

    @discardableResult
    func setMuted(_ muted: Bool) -> Bool {
        guard let id = defaultOutputDeviceID() else { return false }
        var address = Self.muteAddress
        guard AudioObjectHasProperty(id, &address) else { return false }
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    @discardableResult
    func setDefaultDevice(_ id: UInt32) -> Bool {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var value = AudioObjectID(id)
        return AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &value) == noErr
    }

    // MARK: Observing

    func startObserving(onChange: @escaping @MainActor () -> Void) {
        stopObserving()
        self.onChange = onChange
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            let address = Self.address(selector)
            let block = makeListener()
            var mutableAddress = address
            if AudioObjectAddPropertyListenerBlock(system, &mutableAddress, .main, block) == noErr {
                systemListeners.append((address, block))
            }
        }
        observeDefaultDevice()
    }

    func stopObserving() {
        for (address, block) in systemListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(system, &address, .main, block)
        }
        systemListeners.removeAll()
        removeDeviceListeners()
        onChange = nil
    }

    private func makeListener() -> AudioObjectPropertyListenerBlock {
        { [weak self] _, _ in
            // Registered on the main queue.
            MainActor.assumeIsolated { self?.propertyChanged() }
        }
    }

    private func propertyChanged() {
        // The default device may have changed: follow it so its volume and mute keep reporting.
        if deviceListeners.first?.0 != defaultOutputDeviceID() {
            observeDefaultDevice()
        }
        onChange?()
    }

    private func observeDefaultDevice() {
        removeDeviceListeners()
        guard let id = defaultOutputDeviceID() else { return }
        for address in [Self.volumeAddress, Self.muteAddress] {
            var mutableAddress = address
            guard AudioObjectHasProperty(id, &mutableAddress) else { continue }
            let block = makeListener()
            if AudioObjectAddPropertyListenerBlock(id, &mutableAddress, .main, block) == noErr {
                deviceListeners.append((id, address, block))
            }
        }
    }

    private func removeDeviceListeners() {
        for (id, address, block) in deviceListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(id, &address, .main, block)
        }
        deviceListeners.removeAll()
    }

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}
