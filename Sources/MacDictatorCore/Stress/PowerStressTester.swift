import Foundation

public final class PowerStressTester: @unchecked Sendable {
    private var workerProcesses: [Process] = []
    private var isRunning = false
    private let lock = NSLock()

    public init() {}

    deinit {
        stop()
    }

    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunning
    }

    public func start(threadCount: Int = 8) {
        lock.lock()
        defer { lock.unlock() }

        guard !isRunning else { return }
        isRunning = true

        let script = """
        while true; do
            :
        done
        """

        for _ in 0..<threadCount {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/sh")
            proc.arguments = ["-c", script]
            do {
                try proc.run()
                workerProcesses.append(proc)
            } catch {
                print("Failed to spawn stress worker: \(error)")
            }
        }
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        isRunning = false
        for proc in workerProcesses {
            proc.terminate()
        }
        workerProcesses.removeAll()
    }
}
