import Foundation

/// Coordinates component observations at the end of a document transaction.
/// Source inputs still arrive through the render tree; registered node signals
/// cover live membership and the Context dependencies each component read. The
/// auxiliary revision preserves manually constructed Context invalidation;
/// mounted components observe their own subscriptions, never a broad publisher.
final class NativeComponentUpdates: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = false
    @MainActor private(set) var revision: UInt64 = 0
    @MainActor private weak var lastPresentation: NativePresentationCommit?
    @MainActor private var subscriptions: [ObjectIdentifier: WeakSubscription] = [:]
    @MainActor private var registrationsSincePrune = 0

    private final class WeakSubscription {
        weak var value: NativeComponentSubscription?
        init(_ value: NativeComponentSubscription) { self.value = value }
    }

    @MainActor func attach(_ subscription: NativeComponentSubscription) {
        registrationsSincePrune += 1
        if registrationsSincePrune >= 64 {
            subscriptions = subscriptions.filter { $0.value.value != nil }
            registrationsSincePrune = 0
        }
        subscriptions[ObjectIdentifier(subscription)] = WeakSubscription(subscription)
    }

    @MainActor func detach(_ subscription: NativeComponentSubscription) {
        subscriptions.removeValue(forKey: ObjectIdentifier(subscription))
    }

    // Store listeners are Sendable. Defer SwiftUI notification until the owning
    // MainActor transaction has finished, even if a Store callback is nested.
    func invalidate() {
        lock.lock(); pending = true; lock.unlock()
    }

    @MainActor func flush(state: OpenUIState, changes: NativeLiveElementIndex.Update) {
        lock.lock()
        let changed = pending
        pending = false
        lock.unlock()
        if changed { revision &+= 1 }
        let presentation = state.nativePresentation
        // begin() initializes a newly attached node from this same completed
        // commit. A replay/no-op cannot change its reads or presentation inputs.
        guard lastPresentation !== presentation else { return }
        // Resolve each mounted node once against the completed transaction.
        // Weak registrations never keep a view, document or language graph alive.
        let active = subscriptions.values.compactMap(\.value)
        if active.count != subscriptions.count {
            subscriptions = subscriptions.filter { $0.value.value != nil }
        }
        for subscription in active {
            subscription.refresh(state: state, changes: changes, auxiliaryChanged: changed)
        }
        // Node callbacks may enqueue another mutation. The owning State drains
        // it after this flush; its newer commit must still reach every node.
        lastPresentation = presentation
    }
}
