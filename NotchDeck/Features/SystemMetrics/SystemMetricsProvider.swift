import Foundation

/// CPU, memory (with memory pressure) and battery in the command center.
///
/// Energy rules:
/// - CPU and memory are sampled only while one of their rows is on screen, every
///   `samplingInterval` with generous timer tolerance, and not at all otherwise.
/// - Battery and memory pressure are event-driven (IOKit power-source notifications and a
///   dispatch memory-pressure source); nothing polls them.
///
/// Plugging in the charger shows a brief "Charging" peek.
@MainActor
final class SystemMetricsProvider: ActivityProvider {
    let source = ActivitySource(rawValue: "systemMetrics")

    static let samplingInterval: Duration = .seconds(2)

    enum ID {
        static let cpu = "cpu"
        static let memory = "memory"
        static let battery = "battery"
        static let charging = "charging"
    }

    /// Command-center activities never take the notch; priority only orders the list.
    enum Order {
        static let cpu = ActivityPriority(rawValue: 13)
        static let memory = ActivityPriority(rawValue: 12)
        static let battery = ActivityPriority(rawValue: 11)
    }

    private var publisher: ActivityPublisher?
    private let statistics: any SystemStatisticsReading
    private let power: any PowerSourceMonitoring
    private let schedulesSampling: Bool
    private var samplingTask: Task<Void, Never>?
    private var pressureSource: (any DispatchSourceMemoryPressure)?

    private var previousTicks: CPUTicks?
    private(set) var cpuUsage: Double?
    private(set) var memory: MemoryUsage?
    private(set) var pressure: MemoryPressure = .normal
    private(set) var battery: BatteryStatus?

    /// - Parameter schedulesSampling: When `false`, samples are taken only when `sample()` is called (tests).
    init(
        statistics: any SystemStatisticsReading = MachSystemStatistics(),
        power: any PowerSourceMonitoring = IOKitPowerSourceMonitor(),
        schedulesSampling: Bool = true
    ) {
        self.statistics = statistics
        self.power = power
        self.schedulesSampling = schedulesSampling
    }

    var isSampling: Bool { samplingTask != nil }

    // MARK: ActivityProvider

    func start(publisher: ActivityPublisher) {
        self.publisher = publisher
        previousTicks = statistics.cpuTicks()
        memory = statistics.memoryUsage()
        pressure = statistics.memoryPressure()
        battery = power.battery
        power.startMonitoring { [weak self] in self?.powerSourceChanged() }
        if schedulesSampling { observeMemoryPressure() }
        publishAll()
    }

    func stop() {
        samplingTask?.cancel()
        samplingTask = nil
        pressureSource?.cancel()
        pressureSource = nil
        power.stopMonitoring()
        publisher = nil
    }

    func displayedActivitiesChanged(_ ids: Set<NotchActivity.ID>) {
        let needsSampling = !ids.isDisjoint(with: [ID.cpu, ID.memory])
        if needsSampling, samplingTask == nil {
            startSampling()
        } else if !needsSampling {
            samplingTask?.cancel()
            samplingTask = nil
        }
    }

    // MARK: Sampling

    private func startSampling() {
        guard schedulesSampling else {
            // Tests drive sampling explicitly; just mark it as running.
            samplingTask = Task {}
            return
        }
        samplingTask = Task { [weak self] in
            // A quick first sample so the CPU value reflects now, not the time since the last look.
            self?.previousTicks = self?.statistics.cpuTicks()
            try? await Task.sleep(for: .milliseconds(500))
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: Self.samplingInterval, tolerance: .milliseconds(500))
            }
        }
    }

    /// Reads CPU and memory once and republishes them.
    func sample() {
        if let ticks = statistics.cpuTicks() {
            if let previousTicks, let usage = CPUTicks.usage(from: previousTicks, to: ticks) {
                cpuUsage = usage
            }
            previousTicks = ticks
        }
        memory = statistics.memoryUsage() ?? memory
        pressure = statistics.memoryPressure()
        publishCPU()
        publishMemory()
    }

    private func observeMemoryPressure() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.memoryPressureChanged() }
        }
        source.resume()
        pressureSource = source
    }

    func memoryPressureChanged() {
        pressure = statistics.memoryPressure()
        memory = statistics.memoryUsage() ?? memory
        publishMemory()
    }

    func powerSourceChanged() {
        let old = battery
        battery = power.battery
        guard battery != old else { return }
        publishBattery()
        if let battery, let old, battery.isPluggedIn, !old.isPluggedIn {
            publisher?.publish(Self.chargingActivity(battery, now: .now, source: source))
        } else if battery?.isPluggedIn == false {
            publisher?.withdraw(id: ID.charging)
        }
    }

    // MARK: Publishing

    private func publishAll() {
        publishCPU()
        publishMemory()
        publishBattery()
    }

    private func publishCPU() {
        publisher?.publish(Self.cpuActivity(usage: cpuUsage, source: source))
    }

    private func publishMemory() {
        guard let memory else { return }
        publisher?.publish(Self.memoryActivity(memory, pressure: pressure, source: source))
    }

    private func publishBattery() {
        if let battery {
            publisher?.publish(Self.batteryActivity(battery, source: source))
        } else {
            publisher?.withdraw(id: ID.battery)
        }
    }

    // MARK: Activities

    private static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    static func cpuActivity(usage: Double?, source: ActivitySource) -> NotchActivity {
        let accent: ActivityAccent = switch usage ?? 0 {
        case 0.85...: .red
        case 0.6...: .orange
        default: .green
        }
        return NotchActivity(
            id: ID.cpu,
            source: source,
            kind: .system,
            priority: Order.cpu,
            placement: .commandCenter,
            title: "CPU",
            subtitle: usage.map { "\(percent($0)) in use" } ?? "Measuring…",
            presentation: ActivityPresentation(
                symbolName: "cpu",
                accent: accent,
                content: .metric(MetricContent(value: usage ?? 0, valueText: usage.map(percent) ?? "–"))
            )
        )
    }

    static func memoryActivity(_ memory: MemoryUsage, pressure: MemoryPressure, source: ActivitySource) -> NotchActivity {
        NotchActivity(
            id: ID.memory,
            source: source,
            kind: .system,
            priority: Order.memory,
            placement: .commandCenter,
            title: "Memory",
            subtitle: "\(memory.text) · Pressure \(pressure.title.lowercased())",
            presentation: ActivityPresentation(
                symbolName: "memorychip",
                accent: pressure.accent,
                content: .metric(MetricContent(value: memory.fraction, valueText: percent(memory.fraction)))
            )
        )
    }

    static func batteryActivity(_ battery: BatteryStatus, source: ActivitySource) -> NotchActivity {
        NotchActivity(
            id: ID.battery,
            source: source,
            kind: .system,
            priority: Order.battery,
            placement: .commandCenter,
            title: "Battery",
            subtitle: battery.stateText,
            presentation: ActivityPresentation(
                symbolName: battery.symbolName,
                accent: battery.accent,
                content: .metric(MetricContent(value: battery.level, valueText: battery.percentText))
            )
        )
    }

    static let chargingPeekDuration: TimeInterval = 3

    static func chargingActivity(_ battery: BatteryStatus, now: Date, source: ActivitySource) -> NotchActivity {
        NotchActivity(
            id: ID.charging,
            source: source,
            kind: .system,
            priority: .passive,
            title: battery.isCharging ? "Charging" : "Connected to power",
            subtitle: battery.percentText,
            expiresAt: now.addingTimeInterval(chargingPeekDuration),
            presentation: ActivityPresentation(
                symbolName: "bolt.fill",
                accent: .green,
                compactAccessory: .text(battery.percentText),
                revealsOnUpdate: true
            )
        )
    }
}
