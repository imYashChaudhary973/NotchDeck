import Foundation
import Testing
@testable import NotchDeck

@MainActor
final class FakeStatistics: SystemStatisticsReading {
    var ticks = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
    var memory = MemoryUsage(usedBytes: 8 << 30, totalBytes: 16 << 30)
    var pressure = MemoryPressure.normal
    private(set) var cpuReads = 0

    func cpuTicks() -> CPUTicks? {
        cpuReads += 1
        return ticks
    }

    func memoryUsage() -> MemoryUsage? { memory }
    func memoryPressure() -> MemoryPressure { pressure }
}

@MainActor
final class FakePowerSource: PowerSourceMonitoring {
    var battery: BatteryStatus?
    private(set) var isMonitoring = false
    private var onChange: (@MainActor () -> Void)?

    init(battery: BatteryStatus?) {
        self.battery = battery
    }

    func startMonitoring(onChange: @escaping @MainActor () -> Void) {
        isMonitoring = true
        self.onChange = onChange
    }

    func stopMonitoring() {
        isMonitoring = false
        onChange = nil
    }

    func change(to battery: BatteryStatus?) {
        self.battery = battery
        onChange?()
    }
}

struct SystemMetricsValueTests {
    @Test func cpuUsageIsBusyTicksOverTotalTicks() {
        let a = CPUTicks(user: 100, system: 50, idle: 800, nice: 50)
        let b = CPUTicks(user: 160, system: 70, idle: 900, nice: 70)

        // busy +100, idle +100.
        #expect(CPUTicks.usage(from: a, to: b) == 0.5)
        #expect(CPUTicks.usage(from: a, to: a) == nil)
        #expect(CPUTicks.usage(from: b, to: a) == nil)
    }

    @Test func memoryFractionAndText() {
        let memory = MemoryUsage(usedBytes: 12 << 30, totalBytes: 16 << 30)
        #expect(memory.fraction == 0.75)
        #expect(memory.text == "12.0 of 16 GB")
        #expect(MemoryUsage(usedBytes: 1, totalBytes: 0).fraction == 0)
    }

    @Test func batteryPresentation() {
        let low = BatteryStatus(level: 0.1, isPluggedIn: false, isCharging: false, isCharged: false)
        #expect(low.symbolName == "battery.0")
        #expect(low.accent == .red)
        #expect(low.stateText == "On battery")

        let charging = BatteryStatus(level: 0.6, isPluggedIn: true, isCharging: true, isCharged: false)
        #expect(charging.symbolName == "battery.100.bolt")
        #expect(charging.stateText == "Charging")
        #expect(charging.percentText == "60%")

        #expect(BatteryStatus(level: 1, isPluggedIn: true, isCharging: false, isCharged: true).stateText == "Charged")
        #expect(BatteryStatus(level: 0.8, isPluggedIn: true, isCharging: false, isCharged: false).stateText == "Plugged in, not charging")
        #expect(BatteryStatus(level: 0.7, isPluggedIn: false, isCharging: false, isCharged: false).symbolName == "battery.75")
    }
}

@MainActor
struct SystemMetricsProviderTests {
    let engine = ActivityEngine(schedulesExpiry: false)
    let statistics = FakeStatistics()
    let source = ActivitySource(rawValue: "systemMetrics")

    private func key(_ id: String) -> ActivityKey {
        ActivityKey(source: source, id: id)
    }

    private func battery(_ level: Double, pluggedIn: Bool) -> BatteryStatus {
        BatteryStatus(level: level, isPluggedIn: pluggedIn, isCharging: pluggedIn, isCharged: false)
    }

    @Test func publishesCommandCenterMetricsThatNeverTakeTheNotch() {
        let power = FakePowerSource(battery: battery(0.5, pluggedIn: false))
        engine.register(SystemMetricsProvider(statistics: statistics, power: power, schedulesSampling: false))

        #expect(engine.resolution.primary == nil)
        #expect(Set(engine.resolution.queued.map(\.id)) == [SystemMetricsProvider.ID.cpu, SystemMetricsProvider.ID.memory, SystemMetricsProvider.ID.battery])
        #expect(engine.resolution.queued.allSatisfy { $0.placement == .commandCenter })
        #expect(power.isMonitoring)
    }

    @Test func macsWithoutABatteryShowNoBatteryRow() {
        engine.register(SystemMetricsProvider(statistics: statistics, power: FakePowerSource(battery: nil), schedulesSampling: false))

        #expect(engine.activity(for: key(SystemMetricsProvider.ID.battery)) == nil)
    }

    @Test func samplesOnlyWhileCPUOrMemoryIsDisplayed() {
        let provider = SystemMetricsProvider(statistics: statistics, power: FakePowerSource(battery: nil), schedulesSampling: false)
        engine.register(provider)
        #expect(!provider.isSampling)

        engine.updateDisplayedActivities([key(SystemMetricsProvider.ID.battery)])
        #expect(!provider.isSampling)

        engine.updateDisplayedActivities([key(SystemMetricsProvider.ID.cpu)])
        #expect(provider.isSampling)

        engine.updateDisplayedActivities([])
        #expect(!provider.isSampling)
    }

    @Test func sampleComputesCPUUsageAndPublishesIt() {
        let provider = SystemMetricsProvider(statistics: statistics, power: FakePowerSource(battery: nil), schedulesSampling: false)
        engine.register(provider)
        #expect(engine.activity(for: key(SystemMetricsProvider.ID.cpu))?.subtitle == "Measuring…")

        statistics.ticks = CPUTicks(user: 25, system: 0, idle: 75, nice: 0)
        provider.sample()

        let cpu = engine.activity(for: key(SystemMetricsProvider.ID.cpu))
        #expect(cpu?.presentation.content == .metric(MetricContent(value: 0.25, valueText: "25%")))
        #expect(cpu?.presentation.accent == .green)
    }

    @Test func memoryPressureColorsTheMemoryRow() {
        let provider = SystemMetricsProvider(statistics: statistics, power: FakePowerSource(battery: nil), schedulesSampling: false)
        engine.register(provider)

        statistics.pressure = .critical
        provider.memoryPressureChanged()

        let memory = engine.activity(for: key(SystemMetricsProvider.ID.memory))
        #expect(memory?.presentation.accent == .red)
        #expect(memory?.subtitle?.contains("critical") == true)
    }

    @Test func pluggingInShowsABriefChargingPeek() {
        let power = FakePowerSource(battery: battery(0.4, pluggedIn: false))
        engine.register(SystemMetricsProvider(statistics: statistics, power: power, schedulesSampling: false))

        power.change(to: battery(0.4, pluggedIn: true))

        let charging = engine.resolution.primary
        #expect(charging?.id == SystemMetricsProvider.ID.charging)
        #expect(charging?.presentation.revealsOnUpdate == true)
        #expect(charging?.expiresAt != nil)
        #expect(engine.activity(for: key(SystemMetricsProvider.ID.battery))?.subtitle == "Charging")

        power.change(to: battery(0.4, pluggedIn: false))
        #expect(engine.resolution.primary == nil)
    }

    @Test func percentageChangesDoNotShowTheChargingPeek() {
        let power = FakePowerSource(battery: battery(0.4, pluggedIn: true))
        engine.register(SystemMetricsProvider(statistics: statistics, power: power, schedulesSampling: false))

        power.change(to: battery(0.41, pluggedIn: true))

        #expect(engine.resolution.primary == nil)
    }

    @Test func stoppingStopsMonitoring() {
        let power = FakePowerSource(battery: nil)
        let provider = SystemMetricsProvider(statistics: statistics, power: power, schedulesSampling: false)
        engine.register(provider)
        engine.updateDisplayedActivities([key(SystemMetricsProvider.ID.cpu)])

        engine.unregister(provider.source)

        #expect(!power.isMonitoring)
        #expect(!provider.isSampling)
        #expect(engine.resolution == .empty)
    }
}
