import DeckKit
import Foundation
import IOKit
import IOKit.ps

final class SystemTelemetryMonitor {
    static let shared = SystemTelemetryMonitor()

    private struct CPUTicks {
        var user: UInt64
        var system: UInt64
        var idle: UInt64
        var nice: UInt64

        var total: UInt64 {
            user + system + idle + nice
        }
    }

    private struct BatterySample {
        var percent: Double?
        var isCharging: Bool?
        var powerSource: String?
    }

    private struct CoreSample {
        var sampledAt: Date
        var cpuLoadPercent: Double?
        var memoryUsedPercent: Double?
        var gpuLoadPercent: Double?
        var thermalPressurePercent: Double?
        var thermalState: DeckThermalState?
        var temperatureCelsius: Double?
        var batteryPercent: Double?
        var isCharging: Bool?
        var powerSource: String?
    }

    private let lock = NSLock()
    private var previousCPUTicks: [CPUTicks]?
    private var cachedSample: CoreSample?
    private var cachedAt: Date = .distantPast
    private let minSampleInterval: TimeInterval = 0.8

    private init() {}

    func snapshot(windowCount: Int, sessionCount: Int) -> DeckSystemTelemetry {
        let core = currentCoreSample()
        return DeckSystemTelemetry(
            sampledAt: core.sampledAt,
            cpuLoadPercent: core.cpuLoadPercent,
            memoryUsedPercent: core.memoryUsedPercent,
            gpuLoadPercent: core.gpuLoadPercent,
            thermalPressurePercent: core.thermalPressurePercent,
            thermalState: core.thermalState,
            temperatureCelsius: core.temperatureCelsius,
            batteryPercent: core.batteryPercent,
            isCharging: core.isCharging,
            powerSource: core.powerSource,
            windowCount: windowCount,
            sessionCount: sessionCount
        )
    }
}

private extension SystemTelemetryMonitor {
    private func currentCoreSample() -> CoreSample {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        if let cachedSample, now.timeIntervalSince(cachedAt) < minSampleInterval {
            return cachedSample
        }

        let thermal = readThermalState()
        let battery = readBattery()
        let sample = CoreSample(
            sampledAt: now,
            cpuLoadPercent: readCPULoadPercent(),
            memoryUsedPercent: readMemoryUsedPercent(),
            gpuLoadPercent: readGPULoadPercent(),
            thermalPressurePercent: thermal.pressure,
            thermalState: thermal.state,
            temperatureCelsius: nil,
            batteryPercent: battery.percent,
            isCharging: battery.isCharging,
            powerSource: battery.powerSource
        )
        cachedSample = sample
        cachedAt = now
        return sample
    }

    func readCPULoadPercent() -> Double? {
        var cpuInfo: processor_info_array_t?
        var processorCount: natural_t = 0
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &cpuInfo,
            &infoCount
        )
        guard result == KERN_SUCCESS, let cpuInfo else {
            return nil
        }

        defer {
            let size = vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: cpuInfo)), size)
        }

        let statesPerCPU = Int(CPU_STATE_MAX)
        let info = UnsafeBufferPointer(start: cpuInfo, count: Int(infoCount))
        let ticks: [CPUTicks] = (0..<Int(processorCount)).map { index in
            let offset = index * statesPerCPU
            return CPUTicks(
                user: cpuTick(info[offset + Int(CPU_STATE_USER)]),
                system: cpuTick(info[offset + Int(CPU_STATE_SYSTEM)]),
                idle: cpuTick(info[offset + Int(CPU_STATE_IDLE)]),
                nice: cpuTick(info[offset + Int(CPU_STATE_NICE)])
            )
        }

        guard !ticks.isEmpty else { return nil }

        defer { previousCPUTicks = ticks }

        guard let previousCPUTicks, previousCPUTicks.count == ticks.count else {
            let total = ticks.reduce(UInt64(0)) { $0 + $1.total }
            let idle = ticks.reduce(UInt64(0)) { $0 + $1.idle }
            guard total > 0 else { return nil }
            return clampPercent(100.0 * Double(total - idle) / Double(total))
        }

        var busyDelta: UInt64 = 0
        var totalDelta: UInt64 = 0
        for (current, previous) in zip(ticks, previousCPUTicks) {
            let total = current.total.saturatingSubtract(previous.total)
            let idle = current.idle.saturatingSubtract(previous.idle)
            totalDelta += total
            busyDelta += total.saturatingSubtract(idle)
        }

        guard totalDelta > 0 else { return nil }
        return clampPercent(100.0 * Double(busyDelta) / Double(totalDelta))
    }

    func readMemoryUsedPercent() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize = vm_size_t()
        host_page_size(mach_host_self(), &pageSize)

        let freePages = UInt64(stats.free_count) + UInt64(stats.speculative_count)
        let freeBytes = freePages * UInt64(pageSize)
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard totalBytes > 0 else { return nil }

        let usedBytes = totalBytes > freeBytes ? totalBytes - freeBytes : 0
        return clampPercent(100.0 * Double(usedBytes) / Double(totalBytes))
    }

    func readGPULoadPercent() -> Double? {
        guard let matching = IOServiceMatching("IOAccelerator") else {
            return nil
        }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var values: [Double] = []
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }

            guard let unmanaged = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            ) else {
                continue
            }

            guard let stats = unmanaged.takeRetainedValue() as? [String: Any] else {
                continue
            }

            for key in ["Device Utilization %", "Renderer Utilization %"] {
                if let number = stats[key] as? NSNumber {
                    values.append(number.doubleValue)
                }
            }
        }

        guard !values.isEmpty else { return nil }
        return clampPercent(values.reduce(0, +) / Double(values.count))
    }

    func readThermalState() -> (state: DeckThermalState, pressure: Double) {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return (.nominal, 10)
        case .fair:
            return (.fair, 35)
        case .serious:
            return (.serious, 70)
        case .critical:
            return (.critical, 100)
        @unknown default:
            return (.nominal, 10)
        }
    }

    private func readBattery() -> BatterySample {
        let powerInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sourceList = IOPSCopyPowerSourcesList(powerInfo).takeRetainedValue() as [CFTypeRef]

        for source in sourceList {
            guard let description = IOPSGetPowerSourceDescription(powerInfo, source)?
                .takeUnretainedValue() as? [String: Any] else {
                continue
            }

            let current = description[kIOPSCurrentCapacityKey] as? Int
            let max = description[kIOPSMaxCapacityKey] as? Int
            let percent = current.flatMap { current in
                max.flatMap { maxValue -> Double? in
                    guard maxValue > 0 else { return nil }
                    return clampPercent(100.0 * Double(current) / Double(maxValue))
                }
            }

            return BatterySample(
                percent: percent,
                isCharging: description[kIOPSIsChargingKey] as? Bool,
                powerSource: description[kIOPSPowerSourceStateKey] as? String
            )
        }

        return BatterySample(percent: nil, isCharging: nil, powerSource: nil)
    }

    func clampPercent(_ value: Double) -> Double {
        max(0, min(100, value))
    }

    func cpuTick(_ value: integer_t) -> UInt64 {
        UInt64(UInt32(bitPattern: value))
    }
}

private extension UInt64 {
    func saturatingSubtract(_ other: UInt64) -> UInt64 {
        self > other ? self - other : 0
    }
}
