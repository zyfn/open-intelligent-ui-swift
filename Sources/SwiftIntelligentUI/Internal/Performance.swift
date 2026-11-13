import Foundation

/// Opt-in, content-free measurements for this SDK's local presentation work.
/// Reading a snapshot never changes the renderer, state or language contract.
public enum IntelligentUIPerformance {
    public struct Sample: Sendable {
        public let count: UInt64
        public let totalNanoseconds: UInt64
    }

    public static var isEnabled: Bool {
        get { storage.enabled }
        set { storage.enabled = newValue }
    }

    public static func reset() { storage.reset() }
    public static func snapshot() -> [String: Sample] { storage.snapshot() }

    static func record(_ name: String, nanoseconds: UInt64 = 0) {
        storage.record(name, nanoseconds: nanoseconds)
    }

    static func measure<T>(_ name: String, _ operation: () throws -> T) rethrows -> T {
        guard isEnabled else { return try operation() }
        let start = DispatchTime.now().uptimeNanoseconds
        defer { record(name, nanoseconds: DispatchTime.now().uptimeNanoseconds - start) }
        return try operation()
    }

    private static let storage = Storage()

    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var active = false
        private var samples: [String: Sample] = [:]

        var enabled: Bool {
            get { lock.lock(); defer { lock.unlock() }; return active }
            set { lock.lock(); defer { lock.unlock() }; active = newValue }
        }

        func reset() {
            lock.lock(); defer { lock.unlock() }
            samples.removeAll(keepingCapacity: true)
        }

        func snapshot() -> [String: Sample] {
            lock.lock(); defer { lock.unlock() }
            return samples
        }

        func record(_ name: String, nanoseconds: UInt64) {
            lock.lock(); defer { lock.unlock() }
            guard active, samples[name] != nil || samples.count < 64 else { return }
            let previous = samples[name]
            samples[name] = Sample(count: (previous?.count ?? 0) &+ 1,
                                   totalNanoseconds: (previous?.totalNanoseconds ?? 0) &+ nanoseconds)
        }
    }
}

