import Foundation

public final class LowPowerModeManager: @unchecked Sendable {
    private var isSystemLowPowerModeActive = false
    private var didWeEnableLowPowerMode = false
    private let lock = NSLock()

    public init() {}

    public func setLowPowerMode(enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }

        if enabled && !didWeEnableLowPowerMode {
            // Attempt to engage Low Power Mode
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            task.arguments = ["-a", "lowpowermode", "1"]
            try? task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                didWeEnableLowPowerMode = true
                isSystemLowPowerModeActive = true
            }
        } else if !enabled && didWeEnableLowPowerMode {
            // Restore Low Power Mode
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            task.arguments = ["-a", "lowpowermode", "0"]
            try? task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                didWeEnableLowPowerMode = false
                isSystemLowPowerModeActive = false
            }
        }
    }

    public func cleanup() {
        if didWeEnableLowPowerMode {
            setLowPowerMode(enabled: false)
        }
    }
}
