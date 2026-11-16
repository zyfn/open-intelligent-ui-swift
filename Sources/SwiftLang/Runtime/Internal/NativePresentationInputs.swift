/// Deliberately shallow. A changed reference prop must reach the builder, even
/// when its contents compare equal: custom components can read any of it.
/// Immutable references that really are identical need no recursive tree walk.
func nativePresentationInputsEqual(_ lhs: EvaluatedElement, _ rhs: EvaluatedElement) -> Bool {
    if lhs === rhs { return true }
    guard sameName(lhs.typeName, rhs.typeName), sameName(lhs.statementId, rhs.statementId),
          lhs.partial == rhs.partial, lhs.isSourceComplete == rhs.isSourceComplete,
          lhs.props.count == rhs.props.count else { return false }
    for (left, right) in zip(lhs.props, rhs.props) {
        guard sameName(left.0, right.0), nativePresentationValuesEqual(left.1, right.1) else { return false }
    }
    return lhs.sourceReadiness == rhs.sourceReadiness
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

/// Absence preserves a field's fallback; a stored undefined value does not.
/// Both Query data and tracked Context reads use this same distinction.
func nativePresentationValuesEqual(_ lhs: Value?, _ rhs: Value?) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none): return true
    case (.some(let left), .some(let right)): return nativePresentationValuesEqual(left, right)
    default: return false
    }
}

func nativeQueryStatesEqual(_ lhs: [String: QueryState], _ rhs: [String: QueryState]) -> Bool {
    lhs.count == rhs.count && lhs.allSatisfy { key, left in
        guard let right = rhs[key] else { return false }
        return left.status == right.status && nativePresentationValuesEqual(left.data, right.data)
            && nativePresentationErrorEqual(left.error, right.error)
    }
}

func nativeMutationStatesEqual(_ lhs: [String: MutationState], _ rhs: [String: MutationState]) -> Bool {
    lhs.count == rhs.count && lhs.allSatisfy { key, left in
        guard let right = rhs[key] else { return false }
        // Recreated idle wrappers do not change presentation by themselves;
        // reference-valued results still carry distinct readiness metadata.
        return left.status == right.status && nativePresentationValuesEqual(left.data, right.data)
            && nativePresentationErrorEqual(left.error, right.error)
    }
}

func nativePresentationErrorsEqual(_ lhs: [OpenUIError], _ rhs: [OpenUIError]) -> Bool {
    lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { nativePresentationErrorEqual($0.0, $0.1) }
}

private func nativePresentationErrorEqual(_ lhs: OpenUIError?, _ rhs: OpenUIError?) -> Bool {
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

private func sameName(_ lhs: String?, _ rhs: String?) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none): return true
    case (.some(let left), .some(let right)): return left.utf16.elementsEqual(right.utf16)
    default: return false
    }
}
