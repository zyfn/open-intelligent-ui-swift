import Foundation

/// QueryManager may notify from a tool's executor while a whole batch is still
/// changing. At most one MainActor delivery is queued for this subscription;
/// that delivery reads the current manager snapshot. Query scheduling and tool
/// completion remain owned by QueryManager, not by this publication latch.
final class NativeQueryUpdateDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var queued = false
    private var retired = false

    func enqueue() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !retired, !queued else { return false }
        queued = true
        return true
    }

    func take() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !retired, queued else { return false }
        queued = false
        return true
    }

    func retire() {
        lock.lock(); defer { lock.unlock() }
        retired = true
        queued = false
    }
}
