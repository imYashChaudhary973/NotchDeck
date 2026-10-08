import Foundation

/// Cumulative CPU ticks since boot, summed over all cores.
struct CPUTicks: Equatable, Sendable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64

    var busy: UInt64 { user + system + nice }
    var total: UInt64 { busy + idle }

    /// Fraction of time the CPU was busy between two samples, or nil if no time passed.
    static func usage(from previous: CPUTicks, to current: CPUTicks) -> Double? {
        // Tick counters are 32-bit in the kernel and can wrap; treat a decrease as no data.
        guard current.total > previous.total, current.busy >= previous.busy else { return nil }
        let busy = Double(current.busy - previous.busy)
        let total = Double(current.total - previous.total)
        return min(max(busy / total, 0), 1)
    }
}

/// Physical memory in use, measured like Activity Monitor's "Memory Used"
/// (app memory + wired + compressed).
struct MemoryUsage: Equatable, Sendable {
    var usedBytes: UInt64
    var totalBytes: UInt64

    var fraction: Double {
        totalBytes > 0 ? min(Double(usedBytes) / Double(totalBytes), 1) : 0
    }

    /// "11.2 of 16 GB".
    var text: String {
        let gb = 1_073_741_824.0
        let used = (Double(usedBytes) / gb).formatted(.number.precision(.fractionLength(1)))
        let total = (Double(totalBytes) / gb).formatted(.number.precision(.fractionLength(0)))
        return "\(used) of \(total) GB"
    }
}

/// The system's memory pressure level, as reported by the kernel.
enum MemoryPressure: Equatable, Sendable {
    case normal
    case warning
    case critical

    var title: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Elevated"
        case .critical: "Critical"
        }
    }

    var accent: ActivityAccent {
        switch self {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        }
    }
}

/// The internal battery's state.
struct BatteryStatus: Equatable, Sendable {
    /// 0…1.
    var level: Double
    var isPluggedIn: Bool
    var isCharging: Bool
    var isCharged: Bool

    var percentText: String {
        level.formatted(.percent.precision(.fractionLength(0)))
    }

    var stateText: String {
        if isCharged || (isPluggedIn && level >= 0.995) { return "Charged" }
        if isCharging { return "Charging" }
        if isPluggedIn { return "Plugged in, not charging" }
        return "On battery"
    }

    var symbolName: String {
        if isPluggedIn { return "battery.100.bolt" }
        return switch level {
        case ..<0.13: "battery.0"
        case ..<0.38: "battery.25"
        case ..<0.63: "battery.50"
        case ..<0.88: "battery.75"
        default: "battery.100"
        }
    }

    var accent: ActivityAccent {
        if isPluggedIn { return .green }
        return level <= 0.2 ? .red : .neutral
    }
}

/// Reads CPU and memory statistics. Each call is a cheap kernel query; callers decide how often.
@MainActor
protocol SystemStatisticsReading {
    func cpuTicks() -> CPUTicks?
    func memoryUsage() -> MemoryUsage?
    func memoryPressure() -> MemoryPressure
}

/// Reports battery state and calls back when it changes.
@MainActor
protocol PowerSourceMonitoring: AnyObject {
    /// Nil on Macs without a battery.
    var battery: BatteryStatus? { get }
    func startMonitoring(onChange: @escaping @MainActor () -> Void)
    func stopMonitoring()
}
