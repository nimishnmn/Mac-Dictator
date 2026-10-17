import Foundation
import IOKit

public struct GPUMetrics: Sendable {
    public let utilizationPercent: Double
    public let powerWatts: Double
}

public final class GPUMonitor: @unchecked Sendable {
    private let profile: HardwareProfile
    private let ioReportReader: IOReportPowerReader

    public init(profile: HardwareProfile, ioReportReader: IOReportPowerReader) {
        self.profile = profile
        self.ioReportReader = ioReportReader
    }

    public func sample() -> GPUMetrics {
        let util = readGPUUtilization()
        let ioReportSample = ioReportReader.sampleEnergy()

        let maxGpuTdp = profile.ratedMaxTdpWatts * 0.45
        let modeledWatts = 0.20 + (util / 100.0) * maxGpuTdp

        let finalWatts: Double
        if let measured = ioReportSample.gpuWatts, measured > 0.05 {
            finalWatts = measured
        } else {
            finalWatts = modeledWatts
        }

        return GPUMetrics(
            utilizationPercent: util,
            powerWatts: finalWatts
        )
    }

    private func readGPUUtilization() -> Double {
        let matching = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return 0.0
        }
        defer { IOObjectRelease(iterator) }

        var maxUtil = 0.0
        var service = IOIteratorNext(iterator)

        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let stats = dict["PerformanceStatistics"] as? [String: Any] {
                if let devUtil = stats["Device Utilization %"] as? NSNumber {
                    maxUtil = max(maxUtil, devUtil.doubleValue)
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        return min(100.0, max(0.0, maxUtil))
    }
}
