import CoreFoundation
import Darwin
import Foundation

public final class IOReportPowerReader: @unchecked Sendable {
    private typealias CopyChannelsFunc = @convention(c)
        (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
    private typealias CreateSubFunc = @convention(c)
        (UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> Unmanaged<AnyObject>?
    private typealias CreateSamplesFunc = @convention(c)
        (UnsafeRawPointer?, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateDeltaFunc = @convention(c)
        (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias ChannelStringFunc = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias IntegerValueFunc = @convention(c) (CFDictionary, Int32) -> Int64

    private let createSamples: CreateSamplesFunc?
    private let createDelta: CreateDeltaFunc?
    private let channelName: ChannelStringFunc?
    private let unitLabel: ChannelStringFunc?
    private let integerValue: IntegerValueFunc?

    private var subscription: AnyObject?
    private var subscribedChannels: CFMutableDictionary?

    private var previousSample: CFDictionary?
    private var previousTime: CFAbsoluteTime = 0
    private let lock = NSLock()

    public init() {
        guard let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY) else {
            self.createSamples = nil
            self.createDelta = nil
            self.channelName = nil
            self.unitLabel = nil
            self.integerValue = nil
            return
        }

        func sym<T>(_ name: String, as type: T.Type) -> T? {
            guard let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }

        guard
            let copyChannels = sym("IOReportCopyChannelsInGroup", as: CopyChannelsFunc.self),
            let createSub = sym("IOReportCreateSubscription", as: CreateSubFunc.self),
            let createSamples = sym("IOReportCreateSamples", as: CreateSamplesFunc.self),
            let createDelta = sym("IOReportCreateSamplesDelta", as: CreateDeltaFunc.self),
            let channelName = sym("IOReportChannelGetChannelName", as: ChannelStringFunc.self),
            let unitLabel = sym("IOReportChannelGetUnitLabel", as: ChannelStringFunc.self),
            let integerValue = sym("IOReportSimpleGetIntegerValue", as: IntegerValueFunc.self)
        else {
            self.createSamples = nil
            self.createDelta = nil
            self.channelName = nil
            self.unitLabel = nil
            self.integerValue = nil
            return
        }

        self.createSamples = createSamples
        self.createDelta = createDelta
        self.channelName = channelName
        self.unitLabel = unitLabel
        self.integerValue = integerValue

        if let channels = copyChannels("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue() {
            let desired = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, channels)
            var subbed: Unmanaged<CFMutableDictionary>?
            if let sub = createSub(nil, desired!, &subbed, 0, nil)?.takeRetainedValue(),
               let subbedChannels = subbed?.takeRetainedValue() {
                self.subscription = sub
                self.subscribedChannels = subbedChannels
            }
        }
    }

    public struct EnergySample {
        public let gpuWatts: Double?
        public let cpuWatts: Double?
        public let totalWatts: Double?
    }

    public func sampleEnergy() -> EnergySample {
        lock.lock()
        defer { lock.unlock() }

        guard
            let sub = subscription,
            let subbedChannels = subscribedChannels,
            let createSamples = createSamples,
            let createDelta = createDelta,
            let channelName = channelName,
            let unitLabel = unitLabel,
            let integerValue = integerValue
        else {
            return EnergySample(gpuWatts: nil, cpuWatts: nil, totalWatts: nil)
        }

        let subPtr = Unmanaged.passUnretained(sub).toOpaque()
        guard let current = createSamples(subPtr, subbedChannels, nil)?.takeRetainedValue() else {
            return EnergySample(gpuWatts: nil, cpuWatts: nil, totalWatts: nil)
        }

        let now = CFAbsoluteTimeGetCurrent()
        defer {
            previousSample = current
            previousTime = now
        }

        guard let previous = previousSample, now > previousTime else {
            return EnergySample(gpuWatts: nil, cpuWatts: nil, totalWatts: nil)
        }

        let elapsed = now - previousTime
        guard elapsed > 0.05,
              let delta = createDelta(previous, current, nil)?.takeRetainedValue() as? [String: Any],
              let items = delta["IOReportChannels"] as? [CFDictionary]
        else {
            return EnergySample(gpuWatts: nil, cpuWatts: nil, totalWatts: nil)
        }

        var gpuJoules = 0.0
        var cpuJoules = 0.0
        var totalJoules = 0.0

        for item in items {
            guard let name = channelName(item)?.takeUnretainedValue() as String? else { continue }
            let lower = name.lowercased()
            guard lower.contains("energy") else { continue }

            let raw = Double(integerValue(item, 0))
            guard raw >= 0 else { continue }

            let unit = (unitLabel(item)?.takeUnretainedValue() as String?) ?? ""
            let joules = raw * energyToJoules(unit: unit)

            if lower.contains("gpu") {
                gpuJoules += joules
            } else if lower.contains("cpu") {
                cpuJoules += joules
            }
            totalJoules += joules
        }

        let gpuW = gpuJoules > 0 ? (gpuJoules / elapsed) : nil
        let cpuW = cpuJoules > 0 ? (cpuJoules / elapsed) : nil
        let totalW = totalJoules > 0 ? (totalJoules / elapsed) : nil

        return EnergySample(gpuWatts: gpuW, cpuWatts: cpuW, totalWatts: totalW)
    }

    private func energyToJoules(unit: String) -> Double {
        switch unit.lowercased() {
        case "mj": return 1e-3
        case "uj", "µj": return 1e-6
        case "nj": return 1e-9
        case "j":  return 1.0
        default:   return 1e-9
        }
    }
}
