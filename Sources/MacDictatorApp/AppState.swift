import Combine
import Foundation
import MacDictatorCore
import SwiftUI

@MainActor
public final class AppState: ObservableObject {
    @Published public var reading: PowerReading = .zero
    @Published public var history: [PowerReading] = []
    @Published public var processes: [ThrottledProcessInfo] = []
    @Published public var status: GovernorStatus = .inactive
    @Published public var config: PowerLimitConfig {
        didSet {
            saveConfig()
            governor.config = config
        }
    }
    @Published public var hardwareProfile: HardwareProfile
    @Published public var isStressTesting: Bool = false
    @Published public var stressThreads: Int = 4
    @Published public var selectedTab: Int = 0
    @Published public var isPinned: Bool {
        didSet {
            UserDefaults.standard.set(isPinned, forKey: "MacDictator_IsPinned")
        }
    }
    @Published public var useDirectBatteryGauge: Bool {
        didSet {
            UserDefaults.standard.set(useDirectBatteryGauge, forKey: "MacDictator_DirectBatteryGauge")
            engine.useDirectBatteryGauge = useDirectBatteryGauge
        }
    }

    private let engine: PowerEngine
    private let governor: PowerGovernor
    private let stressTester: PowerStressTester

    private let maxHistoryCount = 60

    public init() {
        let profile = HardwareDetector.detect()
        self.hardwareProfile = profile

        // Load saved config or default
        let savedCpu = UserDefaults.standard.double(forKey: "MacDictator_CpuLimit")
        let savedGpu = UserDefaults.standard.double(forKey: "MacDictator_GpuLimit")
        let savedEnabled = UserDefaults.standard.bool(forKey: "MacDictator_GovernorEnabled")
        self.isPinned = UserDefaults.standard.bool(forKey: "MacDictator_IsPinned")
        let savedDirect = UserDefaults.standard.bool(forKey: "MacDictator_DirectBatteryGauge")
        self.useDirectBatteryGauge = savedDirect

        let initialCpu = savedCpu > 0 ? savedCpu : 5.0
        let initialGpu = savedGpu > 0 ? savedGpu : 3.0

        let initialConfig = PowerLimitConfig(
            isGovernorEnabled: savedEnabled,
            cpuLimitWatts: initialCpu,
            gpuLimitWatts: initialGpu,
            totalSocLimitWatts: initialCpu + initialGpu + 1.5,
            strategy: .dynamicDutyCycle
        )
        self.config = initialConfig

        let eng = PowerEngine(profile: profile)
        eng.useDirectBatteryGauge = savedDirect
        let gov = PowerGovernor(config: initialConfig)
        let str = PowerStressTester()

        self.engine = eng
        self.governor = gov
        self.stressTester = str

        setupCallbacks()
        eng.start(intervalSeconds: 0.5)
    }

    private func setupCallbacks() {
        engine.onPowerSample = { [weak self] newReading, procs in
            guard let self = self else { return }
            let (newStatus, procInfos) = self.governor.evaluate(reading: newReading, processes: procs)

            Task { @MainActor in
                self.reading = newReading
                self.status = newStatus
                self.processes = procInfos

                self.history.append(newReading)
                if self.history.count > self.maxHistoryCount {
                    self.history.removeFirst()
                }
            }
        }
    }

    public func toggleGovernor() {
        config.isGovernorEnabled.toggle()
    }

    public func setCpuLimit(_ watts: Double) {
        config.cpuLimitWatts = max(0.5, min(watts, hardwareProfile.ratedMaxTdpWatts))
        config.totalSocLimitWatts = config.cpuLimitWatts + config.gpuLimitWatts + 1.5
    }

    public func setGpuLimit(_ watts: Double) {
        config.gpuLimitWatts = max(0.5, min(watts, hardwareProfile.ratedMaxTdpWatts * 0.7))
        config.totalSocLimitWatts = config.cpuLimitWatts + config.gpuLimitWatts + 1.5
    }

    public func setStrategy(_ strategy: ThrottleStrategy) {
        config.strategy = strategy
    }

    public func toggleExempt(processName: String) {
        let isCurrentlyExempt = config.exemptProcessNames.contains { $0.lowercased() == processName.lowercased() }
        governor.setExempt(processName: processName, exempt: !isCurrentlyExempt)
        config.exemptProcessNames = governor.config.exemptProcessNames
    }

    public func toggleStressTest() {
        if isStressTesting {
            stressTester.stop()
            isStressTesting = false
        } else {
            stressTester.start(threadCount: stressThreads)
            isStressTesting = true
        }
    }

    public func toggleTelemetryMode() {
        useDirectBatteryGauge.toggle()
    }

    private func saveConfig() {
        UserDefaults.standard.set(config.cpuLimitWatts, forKey: "MacDictator_CpuLimit")
        UserDefaults.standard.set(config.gpuLimitWatts, forKey: "MacDictator_GpuLimit")
        UserDefaults.standard.set(config.isGovernorEnabled, forKey: "MacDictator_GovernorEnabled")
    }

    deinit {
        engine.stop()
        stressTester.stop()
    }
}
