import Combine
import Foundation

public final class PowerEngine: @unchecked Sendable {
    public let profile: HardwareProfile
    private let ioReportReader: IOReportPowerReader
    private let cpuMonitor: CPUMonitor
    private let gpuMonitor: GPUMonitor
    private let processMonitor: ProcessMonitor
    private let displayMonitor: DisplayBrightnessMonitor

    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.macdictator.powerengine", qos: .userInteractive)
    private let lock = NSLock()

    // Configurable telemetry mode: true = 100% pure hardware gas gauge, false = responsive hybrid
    public var useDirectBatteryGauge: Bool = false

    // Calibration anchor across the 60-second hardware battery gas gauge updates
    private var lastBatteryUpdateTime: TimeInterval = 0
    private var calibratedBatteryOffset: Double = 0.0
    private var hasCalibratedOnce: Bool = false

    public var onPowerSample: ((PowerReading, [MonitoredProcess]) -> Void)?

    private(set) public var latestReading: PowerReading = .zero
    private(set) public var latestProcesses: [MonitoredProcess] = []

    public init(profile: HardwareProfile? = nil) {
        let p = profile ?? HardwareDetector.detect()
        self.profile = p
        let ioReport = IOReportPowerReader()
        self.ioReportReader = ioReport
        self.cpuMonitor = CPUMonitor(profile: p)
        self.gpuMonitor = GPUMonitor(profile: p, ioReportReader: ioReport)
        self.processMonitor = ProcessMonitor()
        self.displayMonitor = DisplayBrightnessMonitor()
    }

    public func start(intervalSeconds: Double = 0.5) {
        lock.lock()
        defer { lock.unlock() }

        stopTimer()

        let t = DispatchSource.makeTimerSource(queue: timerQueue)
        let intervalMs = Int(intervalSeconds * 1000.0)
        t.schedule(deadline: .now(), repeating: .milliseconds(intervalMs))
        t.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = t
        t.resume()
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopTimer()
    }

    private func stopTimer() {
        if let t = timer {
            t.cancel()
            timer = nil
        }
    }

    public func sampleOnce() -> (PowerReading, [MonitoredProcess]) {
        return tick()
    }

    @discardableResult
    private func tick() -> (PowerReading, [MonitoredProcess]) {
        let cpu = cpuMonitor.sample()
        let gpu = gpuMonitor.sample()
        let battery = BatteryPowerReader.read()
        let displayWatts = displayMonitor.estimatedDisplayWatts(isLaptop: profile.isLaptop)

        let cpuWatts = cpu.modeledWatts
        let gpuWatts = gpu.powerWatts
        let socWatts = cpuWatts + gpuWatts + (profile.baseIdleWatts * 0.4)

        // Baseline platform power (logic board, RAM, SSD, Wi-Fi, audio)
        let totalLoadFraction = min(1.0, (cpu.totalUtilization + gpu.utilizationPercent) / 100.0)
        let platformWatts = profile.isLaptop ? (1.1 + 1.2 * totalLoadFraction) : (3.5 + 2.0 * totalLoadFraction)

        // Real-time instantaneous modeled power, tracking display brightness and compute load immediately
        let instantLiveWatts = socWatts + displayWatts + platformWatts

        let systemWatts: Double
        let isBattery: Bool

        let now = Date().timeIntervalSince1970
        let rawAgeSeconds: Int? = (battery?.updateTimestamp != nil) ? max(0, Int(now - battery!.updateTimestamp!)) : nil

        if let bat = battery, bat.isDischarging {
            isBattery = true

            // Hardware AppleSmartBattery updates once every 30 to 60 seconds.
            let updateTs = bat.updateTimestamp ?? 0
            if updateTs > 0 && updateTs != lastBatteryUpdateTime {
                lastBatteryUpdateTime = updateTs

                // Plausibility check:
                // If the battery reading is within plausible physical range of the current live load
                // (rejecting stale 50W compilation spike buffers when the system has returned to idle):
                if bat.watts >= (instantLiveWatts * 0.4) && bat.watts <= (instantLiveWatts + 14.0) {
                    calibratedBatteryOffset = bat.watts - instantLiveWatts
                    hasCalibratedOnce = true
                } else if bat.watts > (instantLiveWatts + 14.0) {
                    // Stale spike lingering in battery gas gauge buffer: cap the offset
                    calibratedBatteryOffset = min(calibratedBatteryOffset, 2.0)
                }
            }

            if useDirectBatteryGauge {
                // Pure hardware battery gas gauge reading directly from Texas Instruments bq40z651 chip!
                systemWatts = bat.watts
            } else {
                // Responsive hybrid mode: combines hardware gas gauge calibration with zero-latency display & SoC response
                if hasCalibratedOnce {
                    let calibrated = instantLiveWatts + calibratedBatteryOffset
                    systemWatts = max(1.0, min(120.0, calibrated))
                } else {
                    if bat.watts >= 1.5 && bat.watts <= (instantLiveWatts + 8.0) {
                        calibratedBatteryOffset = bat.watts - instantLiveWatts
                        hasCalibratedOnce = true
                        systemWatts = bat.watts
                    } else {
                        systemWatts = instantLiveWatts
                    }
                }
            }
        } else {
            isBattery = (battery?.isExternalPowerConnected == false)
            systemWatts = instantLiveWatts
        }

        let reading = PowerReading(
            timestamp: Date(),
            cpuPowerWatts: cpuWatts,
            gpuPowerWatts: gpuWatts,
            anePowerWatts: 0.0,
            socTotalWatts: socWatts,
            systemTotalWatts: systemWatts,
            cpuUtilization: cpu.totalUtilization,
            gpuUtilization: gpu.utilizationPercent,
            isBatteryPowered: isBattery,
            rawBatteryWatts: battery?.watts,
            rawBatteryAgeSeconds: rawAgeSeconds
        )

        let procs = processMonitor.sample(currentCpuPowerWatts: cpuWatts)

        lock.lock()
        self.latestReading = reading
        self.latestProcesses = procs
        let handler = self.onPowerSample
        lock.unlock()

        handler?(reading, procs)
        return (reading, procs)
    }
}
