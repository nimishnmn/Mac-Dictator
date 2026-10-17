import Foundation
import IOKit

public enum HardwareDetector {
    public static func detect() -> HardwareProfile {
        let chipName = getSysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        let model = getSysctlString("hw.model") ?? "Mac"
        let totalCores = Int(getSysctlInt32("hw.ncpu") ?? 8)
        let memBytes = getSysctlInt64("hw.memsize") ?? 17179869184

        // Detect core clusters (e.g. Super/Performance vs Efficiency)
        let perfLevel0 = getSysctlInt32("hw.perflevel0.physicalcpu") ?? Int32(totalCores / 2)
        let perfLevel1 = getSysctlInt32("hw.perflevel1.physicalcpu") ?? Int32(totalCores - Int(perfLevel0))

        let perf0Name = getSysctlString("hw.perflevel0.name")?.lowercased() ?? ""
        let perf1Name = getSysctlString("hw.perflevel1.name")?.lowercased() ?? ""

        var pCores: Int
        var eCores: Int

        if perf0Name.contains("super") || perf0Name.contains("performance") {
            pCores = Int(perfLevel0)
            eCores = Int(perfLevel1)
        } else if perf1Name.contains("super") || perf1Name.contains("performance") {
            pCores = Int(perfLevel1)
            eCores = Int(perfLevel0)
        } else {
            // Default heuristic: on Apple Silicon Pro/Max, majority are P-cores
            if chipName.contains("Pro") || chipName.contains("Max") || chipName.contains("Ultra") {
                pCores = max(1, totalCores - 4)
                eCores = totalCores - pCores
            } else {
                pCores = max(1, totalCores / 2)
                eCores = totalCores - pCores
            }
        }

        let isLaptop = checkIsLaptop()
        let maxTdp = calculateMaxTdp(chipName: chipName, totalCores: totalCores)
        let baseIdle = isLaptop ? 0.6 : 1.5

        return HardwareProfile(
            chipName: chipName,
            modelIdentifier: model,
            totalCores: totalCores,
            performanceCores: pCores,
            efficiencyCores: eCores,
            memoryBytes: memBytes,
            isLaptop: isLaptop,
            baseIdleWatts: baseIdle,
            ratedMaxTdpWatts: maxTdp
        )
    }

    private static func checkIsLaptop() -> Bool {
        let matching = IOServiceMatching("AppleSmartBattery")
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        if entry != 0 {
            IOObjectRelease(entry)
            return true
        }
        return false
    }

    private static func calculateMaxTdp(chipName: String, totalCores: Int) -> Double {
        let upper = chipName.uppercased()
        if upper.contains("ULTRA") { return 80.0 }
        if upper.contains("MAX") { return 60.0 }
        if upper.contains("PRO") { return 45.0 }
        if upper.contains("M5") { return 30.0 }
        if upper.contains("M4") { return 28.0 }
        if upper.contains("M3") { return 25.0 }
        if upper.contains("M2") { return 22.0 }
        if upper.contains("M1") { return 20.0 }
        return Double(totalCores) * 2.5
    }

    private static func getSysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func getSysctlInt32(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    private static func getSysctlInt64(_ name: String) -> Int64? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}
