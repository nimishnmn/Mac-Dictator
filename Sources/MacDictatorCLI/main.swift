import Foundation
import MacDictatorCore

print("⚡ Mac Dictator — Hardware Power Governor")
print("========================================")

let profile = HardwareDetector.detect()
print(String(format: "Hardware: %@ (%@)", profile.chipName, profile.modelIdentifier))
print(String(format: "Cores: %d (%d Super/Performance, %d Efficiency)", profile.totalCores, profile.performanceCores, profile.efficiencyCores))
print(String(format: "Memory: %.1f GB | Rated SoC TDP: %.1f W", profile.memoryGB, profile.ratedMaxTdpWatts))
print("")

var cpuLimit: Double = 5.0
var gpuLimit: Double = 3.0
var governorEnabled = false
var runStress = false

let args = CommandLine.arguments
var i = 1
while i < args.count {
    let arg = args[i]
    if arg == "--cpu" && i + 1 < args.count {
        cpuLimit = Double(args[i + 1]) ?? 5.0
        i += 1
    } else if arg == "--gpu" && i + 1 < args.count {
        gpuLimit = Double(args[i + 1]) ?? 3.0
        i += 1
    } else if arg == "--on" || arg == "--enable" {
        governorEnabled = true
    } else if arg == "--stress" {
        runStress = true
    } else if arg == "--help" || arg == "-h" {
        print("Usage: mac-dictator-cli [options]")
        print("  --cpu <watts>    Set CPU power limit in watts (default: 5.0)")
        print("  --gpu <watts>    Set GPU power limit in watts (default: 3.0)")
        print("  --on             Enable power governor enforcement")
        print("  --stress         Spawn background stress load to test limits")
        exit(0)
    }
    i += 1
}

var config = PowerLimitConfig(
    isGovernorEnabled: governorEnabled,
    cpuLimitWatts: cpuLimit,
    gpuLimitWatts: gpuLimit,
    totalSocLimitWatts: cpuLimit + gpuLimit + 1.0,
    strategy: .dynamicDutyCycle
)

let engine = PowerEngine(profile: profile)
let governor = PowerGovernor(config: config)
let stress = PowerStressTester()

if runStress {
    print("🔥 Spawning synthetic stress test load (4 threads)...")
    stress.start(threadCount: 4)
}

print(String(format: "Governor State: %@ [CPU Limit: %.1f W, GPU Limit: %.1f W]",
             governorEnabled ? "ACTIVE (Enforcing Ceiling)" : "DISABLED (Monitoring Only)",
             cpuLimit, gpuLimit))
print("Sampling power metrics every 500ms. Press Ctrl+C to exit.\n")

signal(SIGINT) { _ in
    print("\nShutting down Mac Dictator...")
    exit(0)
}

engine.onPowerSample = { reading, procs in
    let (status, _) = governor.evaluate(reading: reading, processes: procs)
    let statusIcon = status.isActive ? (status.isThrottling ? "⚠️" : "🟢") : "⚪"

    print(String(format: "\r[%@] CPU: %5.2f W (Cap: %.1fW) | GPU: %5.2f W | Total: %5.2f W (%@) | Util: %4.1f%% | %@ ",
                 statusIcon,
                 reading.cpuPowerWatts,
                 config.cpuLimitWatts,
                 reading.gpuPowerWatts,
                 reading.systemTotalWatts,
                 reading.isBatteryPowered ? "BAT" : "AC",
                 reading.cpuUtilization,
                 status.statusMessage), terminator: "")
    fflush(stdout)
}

engine.start(intervalSeconds: 0.5)

RunLoop.main.run()
