import Foundation
import Testing
@testable import NotchDeck

@MainActor
final class FakeAudioOutput: AudioOutputControlling {
    var state: AudioOutputSnapshot
    private(set) var isObserving = false
    private var onChange: (@MainActor () -> Void)?

    init(_ state: AudioOutputSnapshot) {
        self.state = state
    }

    func snapshot() -> AudioOutputSnapshot { state }

    func setVolume(_ volume: Double) -> Bool {
        guard state.volume != nil else { return false }
        state.volume = volume
        if volume > 0 { state.isMuted = state.isMuted.map { _ in false } }
        return true
    }

    func setMuted(_ muted: Bool) -> Bool {
        guard state.isMuted != nil else { return false }
        state.isMuted = muted
        return true
    }

    func setDefaultDevice(_ id: UInt32) -> Bool {
        state.defaultDeviceID = id
        return true
    }

    func startObserving(onChange: @escaping @MainActor () -> Void) {
        isObserving = true
        self.onChange = onChange
    }

    func stopObserving() {
        isObserving = false
        onChange = nil
    }

    /// Simulates a change made elsewhere (keyboard keys, Control Center).
    func externalChange(_ change: (inout AudioOutputSnapshot) -> Void) {
        change(&state)
        onChange?()
    }
}

@MainActor
struct AudioProviderTests {
    let engine = ActivityEngine(schedulesExpiry: false)
    let key = ActivityKey(source: ActivitySource(rawValue: "audio"), id: AudioProvider.activityID)

    static let speakers = AudioOutputDevice(id: 10, name: "MacBook Pro Speakers", transport: .builtIn)
    static let headphones = AudioOutputDevice(id: 20, name: "AirPods", transport: .bluetooth)

    private func makeOutput(volume: Double? = 0.5, isMuted: Bool? = false) -> FakeAudioOutput {
        FakeAudioOutput(AudioOutputSnapshot(
            devices: [Self.speakers, Self.headphones],
            defaultDeviceID: Self.speakers.id,
            volume: volume,
            isMuted: isMuted
        ))
    }

    private var level: LevelContent? {
        guard case .level(let level) = engine.activity(for: key)?.presentation.content else { return nil }
        return level
    }

    @Test func publishesAVolumeControlWithOutputDevices() {
        let output = makeOutput()
        engine.register(AudioProvider(output: output))

        let activity = engine.activity(for: key)
        #expect(activity?.placement == .commandCenter)
        #expect(activity?.subtitle == "MacBook Pro Speakers")
        #expect(level == LevelContent(value: 0.5, valueText: "50%", adjustActionID: AudioProvider.ActionID.setVolume, muteActionID: AudioProvider.ActionID.toggleMute))
        #expect(activity?.presentation.options?.options.map(\.title) == ["MacBook Pro Speakers", "AirPods"])
        #expect(activity?.presentation.options?.options.map(\.isSelected) == [true, false])
        #expect(output.isObserving)
    }

    @Test func adjustingSetsTheVolume() {
        let output = makeOutput()
        engine.register(AudioProvider(output: output))

        engine.adjust(actionID: AudioProvider.ActionID.setVolume, to: 0.8, on: key)

        #expect(output.state.volume == 0.8)
        #expect(level?.value == 0.8)
    }

    @Test func muteTogglesAndShowsMuted() {
        let output = makeOutput()
        engine.register(AudioProvider(output: output))

        engine.perform(actionID: AudioProvider.ActionID.toggleMute, on: key)

        #expect(output.state.isMuted == true)
        #expect(level?.isMuted == true)
        #expect(level?.valueText == "Muted")
        #expect(engine.activity(for: key)?.presentation.symbolName == "speaker.slash.fill")
    }

    @Test func choosingAnOptionChangesTheOutputDevice() {
        let output = makeOutput()
        engine.register(AudioProvider(output: output))

        engine.perform(actionID: AudioProvider.ActionID.outputPrefix + "20", on: key)

        #expect(output.state.defaultDeviceID == 20)
        #expect(engine.activity(for: key)?.subtitle == "AirPods")
    }

    @Test func externalChangesAreReflected() {
        let output = makeOutput()
        engine.register(AudioProvider(output: output))

        output.externalChange { $0.volume = 0.2 }

        #expect(level?.value == 0.2)
        #expect(engine.activity(for: key)?.presentation.symbolName == "speaker.wave.1.fill")
    }

    @Test func devicesWithoutVolumeControlAreShownAsFixed() {
        engine.register(AudioProvider(output: makeOutput(volume: nil, isMuted: nil)))

        #expect(level?.adjustActionID == nil)
        #expect(level?.muteActionID == nil)
        #expect(level?.valueText == "Fixed")
    }

    @Test func noOutputDeviceMeansNoActivity() {
        let output = FakeAudioOutput(AudioOutputSnapshot())
        engine.register(AudioProvider(output: output))
        #expect(engine.activity(for: key) == nil)
    }

    @Test func scrollingIsIgnoredWhenTheSettingIsOff() {
        let output = makeOutput()
        engine.register(AudioProvider(output: output, scrollAdjustsVolume: { false }))

        #expect(!engine.routeNotchScroll(2))
        #expect(output.state.volume == 0.5)
    }

    @Test func scrollingChangesTheVolumeAndShowsAHUD() {
        let output = makeOutput()
        let provider = AudioProvider(output: output, scrollAdjustsVolume: { true })
        engine.register(provider)

        #expect(engine.routeNotchScroll(2))

        #expect(output.state.volume == 0.5 + 2 * AudioProvider.scrollStep)
        let hud = engine.resolution.primary
        #expect(hud?.key == key)
        #expect(hud?.placement == .notch)
        #expect(hud?.priority == .timeSensitive)
        #expect(hud?.presentation.revealsOnUpdate == true)

        provider.hideHUD()
        #expect(engine.resolution.primary == nil)
        #expect(engine.activity(for: key)?.placement == .commandCenter)
    }

    @Test func scrollingClampsTheVolume() {
        let output = makeOutput(volume: 0.98)
        engine.register(AudioProvider(output: output, scrollAdjustsVolume: { true }))

        engine.routeNotchScroll(5)
        #expect(output.state.volume == 1)

        engine.routeNotchScroll(-100)
        #expect(output.state.volume == 0)
    }

    @Test func stoppingStopsObserving() {
        let output = makeOutput()
        let provider = AudioProvider(output: output)
        engine.register(provider)
        engine.unregister(provider.source)

        #expect(!output.isObserving)
        #expect(engine.activity(for: key) == nil)
    }
}
