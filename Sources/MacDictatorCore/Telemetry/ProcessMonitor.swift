import Darwin
import Foundation

public struct MonitoredProcess: Sendable {
    public let pid: Int32
    public let name: String
    public let cpuPercent: Double
    public let estimatedWatts: Double
}

public final class ProcessMonitor: @unchecked Sendable {
    private struct PreviousProcessState {
        let totalTime: UInt64
        let timestamp: CFAbsoluteTime
    }

    private var previousStates: [Int32: PreviousProcessState] = [:]
    private let lock = NSLock()

    public init() {}

    public func sample(currentCpuPowerWatts: Double) -> [MonitoredProcess] {
        lock.lock()
        defer { lock.unlock() }

        var pids = [Int32](repeating: 0, count: 2048)
        let numPids = proc_listallpids(&pids, Int32(MemoryLayout<Int32>.stride * pids.count))
        guard numPids > 0 else { return [] }

        let now = CFAbsoluteTimeGetCurrent()
        var currentResults: [MonitoredProcess] = []
        var nextStates: [Int32: PreviousProcessState] = [:]
        var totalCpuSum = 0.0

        for i in 0..<Int(numPids) {
            let pid = pids[i]
            guard pid > 1 else { continue } // skip idle / kernel_task

            var taskInfo = proc_taskinfo()
            let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.stride))
            guard size == MemoryLayout<proc_taskinfo>.stride else { continue }

            let totalTime = taskInfo.pti_total_user + taskInfo.pti_total_system
            nextStates[pid] = PreviousProcessState(totalTime: totalTime, timestamp: now)

            if let prev = previousStates[pid] {
                let dt = now - prev.timestamp
                if dt > 0.05 && totalTime >= prev.totalTime {
                    let dTimeNanosecs = Double(totalTime - prev.totalTime)
                    // dTime is in nanoseconds, dt is in seconds
                    let cpuFraction = (dTimeNanosecs / 1_000_000_000.0) / dt
                    let cpuPercent = cpuFraction * 100.0

                    if cpuPercent > 0.5 { // Only track processes using non-trivial CPU
                        var nameBuf = [CChar](repeating: 0, count: 256)
                        _ = proc_name(pid, &nameBuf, 256)
                        let name = String(cString: nameBuf)
                        totalCpuSum += cpuPercent

                        currentResults.append(MonitoredProcess(
                            pid: pid,
                            name: name.isEmpty ? "PID \(pid)" : name,
                            cpuPercent: cpuPercent,
                            estimatedWatts: 0.0
                        ))
                    }
                }
            }
        }

        previousStates = nextStates

        // Assign estimated watts proportional to CPU contribution
        let finalResults: [MonitoredProcess] = currentResults.map { proc in
            let proportion = totalCpuSum > 0 ? (proc.cpuPercent / totalCpuSum) : 0.0
            let watts = max(0.01, currentCpuPowerWatts * proportion)
            return MonitoredProcess(
                pid: proc.pid,
                name: proc.name,
                cpuPercent: proc.cpuPercent,
                estimatedWatts: watts
            )
        }

        // Return sorted by CPU descending
        return finalResults.sorted { $0.cpuPercent > $1.cpuPercent }
    }
}
