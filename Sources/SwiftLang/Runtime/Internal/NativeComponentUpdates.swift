import Combine
import Foundation

/// Components receive their source values through the render tree. This signal
/// covers the other context inputs: Store edits, query lifecycle and document
/// completion/replacement. It owns no language values or alternate state.
final class NativeComponentUpdates: ObservableObject, @unchecked Sendable {
    let objectWillChange = ObservableObjectPublisher()
    private let lock = NSLock()
    private var pending = false
    @MainActor private(set) var revision: UInt64 = 0

    // Store listeners are Sendable. Defer SwiftUI notification until the owning
    // MainActor transaction has finished, even if a Store callback is nested.
    func invalidate() {
        lock.lock(); pending = true; lock.unlock()
    }

    @MainActor func flush() {
        lock.lock()
        let changed = pending
        pending = false
        lock.unlock()
        if changed {
            revision &+= 1
            objectWillChange.send()
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
    case (.some(let left), .some(let right)): return sameValue(left, right)
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
        guard left.0.utf16.elementsEqual(right.0.utf16), sameValue(left.1, right.1) else { return false }
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

private func sameValue(_ lhs: Value, _ rhs: Value) -> Bool {
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
