import Darwin
import Foundation
import IOKit.ps

/// CPU, memory and memory pressure from public Mach and sysctl interfaces.
@MainActor
final class MachSystemStatistics: SystemStatisticsReading {
    private let host = mach_host_self()
    private let pageSize: UInt64

    init() {
        var size = vm_size_t(0)
        pageSize = host_page_size(host, &size) == KERN_SUCCESS ? UInt64(size) : 16_384
    }

    func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        return CPUTicks(
            user: UInt64(ticks.0),   // CPU_STATE_USER
            system: UInt64(ticks.1), // CPU_STATE_SYSTEM
            idle: UInt64(ticks.2),   // CPU_STATE_IDLE
            nice: UInt64(ticks.3)    // CPU_STATE_NICE
        )
    }

    func memoryUsage() -> MemoryUsage? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let appPages = UInt64(stats.internal_page_count) - min(UInt64(stats.purgeable_count), UInt64(stats.internal_page_count))
        let used = (appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * pageSize
        return MemoryUsage(usedBytes: used, totalBytes: ProcessInfo.processInfo.physicalMemory)
    }

    func memoryPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        return switch level {
        case 4: .critical
        case 2: .warning
        default: .normal
        }
    }
}

/// Battery state from IOKit power-source APIs, with change notifications instead of polling.
@MainActor
final class IOKitPowerSourceMonitor: PowerSourceMonitoring {
    private var runLoopSource: CFRunLoopSource?
    private var onChange: (@MainActor () -> Void)?

    var battery: BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else {
                continue
            }
            return BatteryStatus(
                level: Double(current) / Double(max),
                isPluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isCharged: description[kIOPSIsChargedKey] as? Bool ?? false
            )
        }
        return nil
    }

    func startMonitoring(onChange: @escaping @MainActor () -> Void) {
        stopMonitoring()
        self.onChange = onChange
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<IOKitPowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
            // The source is added to the main run loop, so this runs on the main thread.
            MainActor.assumeIsolated { monitor.onChange?() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
    }

    func stopMonitoring() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        onChange = nil
    }
}
