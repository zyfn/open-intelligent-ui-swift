import Combine
import Foundation

/// Coordinates component observations at the end of a document transaction.
/// Source inputs still arrive through the render tree; registered node signals
/// cover live membership and the Context dependencies each component read. The
/// auxiliary revision records Store/Query/terminal changes without owning values.
final class NativeComponentUpdates: ObservableObject, @unchecked Sendable {
    let objectWillChange = ObservableObjectPublisher()
    private let lock = NSLock()
    private var pending = false
    @MainActor private(set) var revision: UInt64 = 0
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
        if changed {
            revision &+= 1
            objectWillChange.send()
        }
        // Resolve each mounted node once against the completed transaction.
        // SwiftUI observes those node signals, not this broad auxiliary signal.
        // Weak registrations never keep a view, document or language graph alive.
        let active = subscriptions.values.compactMap(\.value)
        if active.count != subscriptions.count {
            subscriptions = subscriptions.filter { $0.value.value != nil }
        }
        for subscription in active {
            subscription.refresh(state: state, changes: changes, auxiliaryChanged: changed)
        }
    }
}

func nativeQueryStatesEqual(_ lhs: [String: QueryState], _ rhs: [String: QueryState]) -> Bool {
    lhs.count == rhs.count && lhs.allSatisfy { key, left in
        guard let right = rhs[key] else { return false }
        return left.status == right.status && sameData(left.data, right.data) && sameError(left.error, right.error)
    }
}

func nativeMutationStatesEqual(_ lhs: [String: MutationState], _ rhs: [String: MutationState]) -> Bool {
    lhs.count == rhs.count && lhs.allSatisfy { key, left in
        guard let right = rhs[key] else { return false }
        // Idle fallback wrappers can be newly constructed even when no query
        // lifecycle or context-visible data has changed. Do not deep-serialize
        // their result objects merely to decide whether a component updates.
        return left.status == right.status && sameData(left.data, right.data) && sameError(left.error, right.error)
    }
}

private func sameData(_ lhs: Value?, _ rhs: Value?) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none): return true
    case (.some(let left), .some(let right)): return nativePresentationValuesEqual(left, right)
    default: return false
    }
}

private func sameError(_ lhs: OpenUIError?, _ rhs: OpenUIError?) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none): return true
    case (.some(let left), .some(let right)):
        return left.source == right.source && left.code == right.code
            && sameName(left.message, right.message) && sameName(left.statementId, right.statementId)
            && sameName(left.component, right.component) && left.path == right.path && left.toolName == right.toolName
            && sameName(left.hint, right.hint) && sameName(left.severity, right.severity)
    default: return false
    }
}

/// Deliberately shallow. A changed reference prop must reach the builder, even
/// when its contents compare equal: custom components can read any of it.
/// Immutable references that really are identical need no recursive tree walk.
func nativePresentationInputsEqual(_ lhs: EvaluatedElement, _ rhs: EvaluatedElement) -> Bool {
    if lhs === rhs { return true }
    guard lhs.typeName.utf16.elementsEqual(rhs.typeName.utf16),
          sameName(lhs.statementId, rhs.statementId), lhs.partial == rhs.partial,
          lhs.isSourceComplete == rhs.isSourceComplete, lhs.props.count == rhs.props.count else { return false }
    for (left, right) in zip(lhs.props, rhs.props) {
        guard left.0.utf16.elementsEqual(right.0.utf16), nativePresentationValuesEqual(left.1, right.1) else { return false }
    }
    return lhs.sourceReadiness == rhs.sourceReadiness
}

private func sameName(_ lhs: String?, _ rhs: String?) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none): return true
    case (.some(let left), .some(let right)): return left.utf16.elementsEqual(right.utf16)
    default: return false
    }
}

func nativePresentationValuesEqual(_ lhs: Value, _ rhs: Value) -> Bool {
    switch (lhs, rhs) {
    case (.array(let left), .array(let right)): return left === right
    case (.object(let left), .object(let right)): return left === right
    case (.element(let left), .element(let right)): return left === right
    case (.actionPlan(let left), .actionPlan(let right)): return left === right
    case (.binding(let left), .binding(let right)),
         (.reactiveBinding(let left), .reactiveBinding(let right)): return left === right
    case (.string, .string), (.number, .number), (.boolean, .boolean),
         (.null, .null), (.undefined, .undefined): return lhs.isSameValue(as: rhs)
    default: return false
    }
}
