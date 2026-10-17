import CoreGraphics
import Foundation

public final class DisplayBrightnessMonitor: @unchecked Sendable {
    private typealias GetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private let getBrightness: GetBrightnessFunc?

    public init() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
           let sym = dlsym(handle, "DisplayServicesGetBrightness") {
            self.getBrightness = unsafeBitCast(sym, to: GetBrightnessFunc.self)
        } else {
            self.getBrightness = nil
        }
    }

    /// Returns the normalized brightness of the main built-in display (0.0 ... 1.0)
    public func currentBrightness() -> Double? {
        guard let getBrightness = getBrightness else { return nil }
        var b: Float = 0.0
        let res = getBrightness(CGMainDisplayID(), &b)
        if res == 0 && b >= 0.0 && b <= 1.0 {
            return Double(b)
        }
        return nil
    }

    /// Estimates real-time display power consumption in Watts based on current brightness
    /// Apple Silicon Liquid Retina / Retina displays draw:
    /// - ~0.35W at minimum / off (panel logic & timing controller TCON)
    /// - ~2.0W at 50% brightness
    /// - ~7.5W - 8.5W at 100% brightness (SDR max)
    public func estimatedDisplayWatts(isLaptop: Bool) -> Double {
        guard isLaptop else {
            // External displays are externally powered via wall outlet or USB-PD
            return 0.0
        }

        let b = currentBrightness() ?? 0.5
        let minTconWatts = 0.35
        let maxBacklightWatts = 7.2
        // LED backlight luminous power scales with perceptual gamma ~1.8
        let backlightWatts = maxBacklightWatts * pow(b, 1.8)
        return minTconWatts + backlightWatts
    }
}
