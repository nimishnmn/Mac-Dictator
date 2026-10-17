import Darwin
import Foundation
import MachO

public struct CPUCoreLoad: Sendable {
    public let coreIndex: Int
    public let isPerformanceCore: Bool
    public let loadPercent: Double // 0 - 100%
}

public struct CPUMetrics: Sendable {
    public let totalUtilization: Double // 0 - 100%
    public let pCoreUtilization: Double
    public let eCoreUtilization: Double
    public let modeledWatts: Double
    public let coreLoads: [CPUCoreLoad]
}

public final class CPUMonitor: @unchecked Sendable {
    private let profile: HardwareProfile
    private var previousCpuInfo: processor_info_array_t?
    private var previousNumCpuInfo: mach_msg_type_number_t = 0
    private var previousTime: CFAbsoluteTime = 0
    private let lock = NSLock()

    public init(profile: HardwareProfile) {
        self.profile = profile
    }

    deinit {
        if let prev = previousCpuInfo {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), vm_size_t(previousNumCpuInfo * 4))
        }
    }

    public func sample() -> CPUMetrics {
        lock.lock()
        defer { lock.unlock() }

        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCpuInfo
        )

        guard result == KERN_SUCCESS, let currentCpuInfo = cpuInfo else {
            return CPUMetrics(
                totalUtilization: 0.0,
                pCoreUtilization: 0.0,
                eCoreUtilization: 0.0,
                modeledWatts: profile.baseIdleWatts * 0.5,
                coreLoads: []
            )
        }

        let now = CFAbsoluteTimeGetCurrent()
        defer {
            if let prev = previousCpuInfo {
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), vm_size_t(previousNumCpuInfo * 4))
            }
            previousCpuInfo = currentCpuInfo
            previousNumCpuInfo = numCpuInfo
            previousTime = now
        }

        guard let prev = previousCpuInfo else {
            return CPUMetrics(
                totalUtilization: 0.0,
                pCoreUtilization: 0.0,
                eCoreUtilization: 0.0,
                modeledWatts: profile.baseIdleWatts * 0.5,
                coreLoads: []
            )
        }

        var coreLoads: [CPUCoreLoad] = []
        var totalUser: Int64 = 0
        var totalSystem: Int64 = 0
        var totalIdle: Int64 = 0
        var totalNice: Int64 = 0

        var pCoreLoadSum = 0.0
        var eCoreLoadSum = 0.0
        var pCoreCount = 0
        var eCoreCount = 0

        let pCores = profile.performanceCores

        for i in 0..<Int(numCPUs) {
            let offset = Int32(i) * CPU_STATE_MAX
            let user = Int64(currentCpuInfo[Int(offset + CPU_STATE_USER)] - prev[Int(offset + CPU_STATE_USER)])
            let system = Int64(currentCpuInfo[Int(offset + CPU_STATE_SYSTEM)] - prev[Int(offset + CPU_STATE_SYSTEM)])
            let idle = Int64(currentCpuInfo[Int(offset + CPU_STATE_IDLE)] - prev[Int(offset + CPU_STATE_IDLE)])
            let nice = Int64(currentCpuInfo[Int(offset + CPU_STATE_NICE)] - prev[Int(offset + CPU_STATE_NICE)])

            let busyTicks = max(0, user + system + nice)
            let totalTicks = busyTicks + max(0, idle)
            let load = totalTicks > 0 ? (Double(busyTicks) / Double(totalTicks)) * 100.0 : 0.0

            totalUser += user
            totalSystem += system
            totalIdle += idle
            totalNice += nice

            let isPCore = i < pCores
            if isPCore {
                pCoreLoadSum += load
                pCoreCount += 1
            } else {
                eCoreLoadSum += load
                eCoreCount += 1
            }

            coreLoads.append(CPUCoreLoad(coreIndex: i, isPerformanceCore: isPCore, loadPercent: load))
        }

        let totalBusy = max(0, totalUser + totalSystem + totalNice)
        let totalAll = totalBusy + max(0, totalIdle)
        let overallUtil = totalAll > 0 ? (Double(totalBusy) / Double(totalAll)) * 100.0 : 0.0

        let pCoreAvg = pCoreCount > 0 ? (pCoreLoadSum / Double(pCoreCount)) : 0.0
        let eCoreAvg = eCoreCount > 0 ? (eCoreLoadSum / Double(eCoreCount)) : 0.0

        // Per-core power scaling calibrated to SoC architecture:
        // E-cores max out at ~0.45W each. P-cores max out at ~3.2W each.
        // Idle baseline is around 0.35W.
        let eCoreMaxWattsPerCore = 0.45
        let pCoreMaxWattsPerCore = max(2.5, profile.ratedMaxTdpWatts * 0.75 / Double(max(1, profile.performanceCores)))

        var watts = 0.35 // idle base
        for core in coreLoads {
            let fraction = max(0.0, min(1.0, core.loadPercent / 100.0))
            if core.isPerformanceCore {
                watts += fraction * pCoreMaxWattsPerCore
            } else {
                watts += fraction * eCoreMaxWattsPerCore
            }
        }

        return CPUMetrics(
            totalUtilization: overallUtil,
            pCoreUtilization: pCoreAvg,
            eCoreUtilization: eCoreAvg,
            modeledWatts: watts,
            coreLoads: coreLoads
        )
    }
}
