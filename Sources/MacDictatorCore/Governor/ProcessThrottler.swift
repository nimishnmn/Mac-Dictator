import Darwin
import Foundation

public final class ProcessThrottler: @unchecked Sendable {
    private struct ActiveThrottleState {
        var dutyCycleFraction: Double // 0.05 to 1.0 (1.0 = normal, 0.2 = 20% run time)
        var isQosClamped: Bool
        var lastActionTime: CFAbsoluteTime
        var isCurrentlyPaused: Bool
    }

    private var throttledPids: [Int32: ActiveThrottleState] = [:]
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.macdictator.throttler", qos: .userInteractive)
    private let lock = NSLock()

    // Cycle window in seconds (e.g. 100 milliseconds)
    private let cyclePeriod: Double = 0.10

    public init() {
        startDutyCycleLoop()
    }

    deinit {
        releaseAll()
    }

    public func applyThrottle(pid: Int32, targetDutyCycle: Double, strategy: ThrottleStrategy) {
        lock.lock()
        defer { lock.unlock() }

        guard pid > 1 else { return }

        let clampedDuty = max(0.05, min(1.0, targetDutyCycle))
        var state = throttledPids[pid] ?? ActiveThrottleState(
            dutyCycleFraction: 1.0,
            isQosClamped: false,
            lastActionTime: CFAbsoluteTimeGetCurrent(),
            isCurrentlyPaused: false
        )

        // Apply E-core / Background QoS Clamp
        if !state.isQosClamped {
            _ = setpriority(PRIO_PROCESS, id_t(pid), PRIO_DARWIN_BG)
            state.isQosClamped = true
        }

        // Under eCoreClampOnly strategy, we do not duty-cycle pause the process
        if strategy == .eCoreClampOnly {
            state.dutyCycleFraction = 1.0
            if state.isCurrentlyPaused {
                _ = kill(pid, SIGCONT)
                state.isCurrentlyPaused = false
            }
        } else {
            state.dutyCycleFraction = clampedDuty
        }

        throttledPids[pid] = state
    }

    public func relaxThrottle(pid: Int32, stepUp: Double = 0.20) {
        lock.lock()
        defer { lock.unlock() }

        guard var state = throttledPids[pid] else { return }
        state.dutyCycleFraction = min(1.0, state.dutyCycleFraction + stepUp)

        if state.dutyCycleFraction >= 0.95 {
            // Restore normal priority and ensure running
            if state.isCurrentlyPaused {
                _ = kill(pid, SIGCONT)
            }
            _ = setpriority(PRIO_PROCESS, id_t(pid), 0)
            throttledPids.removeValue(forKey: pid)
        } else {
            throttledPids[pid] = state
        }
    }

    public func release(pid: Int32) {
        lock.lock()
        defer { lock.unlock() }

        if let state = throttledPids.removeValue(forKey: pid) {
            if state.isCurrentlyPaused {
                _ = kill(pid, SIGCONT)
            }
            _ = setpriority(PRIO_PROCESS, id_t(pid), 0)
        }
    }

    public func releaseAll() {
        lock.lock()
        defer { lock.unlock() }

        for (pid, state) in throttledPids {
            if state.isCurrentlyPaused {
                _ = kill(pid, SIGCONT)
            }
            _ = setpriority(PRIO_PROCESS, id_t(pid), 0)
        }
        throttledPids.removeAll()
    }

    public func getThrottledPids() -> [Int32: Double] {
        lock.lock()
        defer { lock.unlock() }
        var result: [Int32: Double] = [:]
        for (pid, state) in throttledPids {
            result[pid] = state.dutyCycleFraction
        }
        return result
    }

    private func startDutyCycleLoop() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        // Sub-cycle resolution: check every 20ms
        t.schedule(deadline: .now(), repeating: .milliseconds(20))
        t.setEventHandler { [weak self] in
            self?.dutyCycleTick()
        }
        self.timer = t
        t.resume()
    }

    private func dutyCycleTick() {
        lock.lock()
        defer { lock.unlock() }

        let now = CFAbsoluteTimeGetCurrent()

        for (pid, var state) in throttledPids {
            // If duty cycle is 100%, keep running
            if state.dutyCycleFraction >= 0.98 {
                if state.isCurrentlyPaused {
                    let ret = kill(pid, SIGCONT)
                    if ret != 0 && errno == ESRCH {
                        throttledPids.removeValue(forKey: pid)
                        continue
                    }
                    state.isCurrentlyPaused = false
                    throttledPids[pid] = state
                }
                continue
            }

            let runDuration = cyclePeriod * state.dutyCycleFraction
            let pauseDuration = cyclePeriod * (1.0 - state.dutyCycleFraction)
            let elapsedInCurrentPhase = now - state.lastActionTime

            if state.isCurrentlyPaused {
                // We are paused; check if pause duration has elapsed
                if elapsedInCurrentPhase >= pauseDuration {
                    let ret = kill(pid, SIGCONT)
                    if ret != 0 && errno == ESRCH {
                        throttledPids.removeValue(forKey: pid)
                        continue
                    }
                    state.isCurrentlyPaused = false
                    state.lastActionTime = now
                    throttledPids[pid] = state
                }
            } else {
                // We are running; check if run duration has elapsed
                if elapsedInCurrentPhase >= runDuration {
                    let ret = kill(pid, SIGSTOP)
                    if ret != 0 && errno == ESRCH {
                        throttledPids.removeValue(forKey: pid)
                        continue
                    }
                    state.isCurrentlyPaused = true
                    state.lastActionTime = now
                    throttledPids[pid] = state
                }
            }
        }
    }
}
