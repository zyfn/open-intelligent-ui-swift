import Combine
import Foundation

/// One immutable, native-only read model. Values still belong to the single
/// language Store; a presentation cannot write or initialize that Store.
@MainActor
final class NativePresentationCommit {
    let root: EvaluatedElement?
    let presentationRoot: NativeSourceReadiness?
    let sourceRevision: Int
    let presentationRevision: Int
    let isComplete: Bool
    let isInterrupted: Bool
    let isQueryLoading: Bool
    let canExecuteActions: Bool
    let isRuntimeLimited: Bool
    let queryStates: [String: QueryState]
    let mutationStates: [String: MutationState]
    let errors: [OpenUIError]
    let storeValues: [OpenUIString: Value]
    let storeRevision: UInt64

    // Only synchronous reentrant fitting needs a retired commit's lookup. In
    // the normal path OpenUIState uses its current live index. This
    // cache is private to the immutable read model, never an alternate engine.
    private var retainedIndex: NativeLiveElementIndex?

    init(root: EvaluatedElement? = nil, presentationRoot: NativeSourceReadiness? = nil,
         sourceRevision: Int = 0, presentationRevision: Int = 0,
         isComplete: Bool = false, isInterrupted: Bool = false, isQueryLoading: Bool = false,
         canExecuteActions: Bool = false, isRuntimeLimited: Bool = false,
         queryStates: [String: QueryState] = [:], mutationStates: [String: MutationState] = [:],
         errors: [OpenUIError] = [], storeValues: [OpenUIString: Value] = [:], storeRevision: UInt64 = 0) {
        self.root = root; self.presentationRoot = presentationRoot
        self.sourceRevision = sourceRevision; self.presentationRevision = presentationRevision
        self.isComplete = isComplete; self.isInterrupted = isInterrupted; self.isQueryLoading = isQueryLoading
        self.canExecuteActions = canExecuteActions; self.isRuntimeLimited = isRuntimeLimited
        self.queryStates = queryStates; self.mutationStates = mutationStates; self.errors = errors
        self.storeValues = storeValues; self.storeRevision = storeRevision
    }

    func hasSameInputs(as other: NativePresentationCommit) -> Bool {
        root === other.root && presentationRoot == other.presentationRoot
            && sourceRevision == other.sourceRevision && presentationRevision == other.presentationRevision
            && isComplete == other.isComplete && isInterrupted == other.isInterrupted
            && isQueryLoading == other.isQueryLoading && canExecuteActions == other.canExecuteActions
            && isRuntimeLimited == other.isRuntimeLimited && storeRevision == other.storeRevision
            && nativeQueryStatesEqual(queryStates, other.queryStates)
            && nativeMutationStatesEqual(mutationStates, other.mutationStates)
            && nativePresentationErrorsEqual(errors, other.errors)
    }

    func fieldValue(form: OpenUIString?, name: OpenUIString) -> Value? {
        nativeUnwrappedFieldValue(form: form, name: name, read: { self.storeValues[$0] })
    }

    func resolve(_ element: EvaluatedElement) -> EvaluatedElement {
        prepareIndex()
        guard let index = retainedIndex else { return element }
        return nativeResolveLiveElement(element, in: index)
    }

    func contains(_ element: EvaluatedElement) -> Bool {
        prepareIndex()
        return retainedIndex?.contains(element) == true
    }

    private func prepareIndex() {
        guard retainedIndex == nil else { return }
        var index = NativeLiveElementIndex()
        index.replaceRoot(root)
        retainedIndex = index
    }

    func isPlanReady(_ plan: ActionPlan) -> Bool {
        guard !isRuntimeLimited else { return false }
        return nativeActionPlanIsReady(plan, canExecuteActions: canExecuteActions,
            stateValue: { self.storeValues[OpenUIString($0)] },
            queryData: { self.queryStates[$0]?.data },
            mutationStatus: { self.mutationStates[$0]?.status })
    }
}

/// SwiftUI subscribes to this single commit, not the intermediate public
/// Published setters. OpenUIState's synchronous queue also protects this setter
/// from reentrant consumers; no callback may overwrite a newer commit.
@MainActor
final class NativePresentationStore: ObservableObject {
    @Published private(set) var snapshot = NativePresentationCommit()

    func commit(_ next: NativePresentationCommit) {
        guard !snapshot.hasSameInputs(as: next) else { return }
        snapshot = next
    }
}

/// Store listeners are Sendable and may run inside the serialized JS bridge.
/// This counter holds no business values, and avoids re-reading an unchanged
/// plain-data Store for every incoming text chunk.
final class NativeStoreRevision: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    func invalidate() { lock.lock(); value &+= 1; lock.unlock() }
    func read() -> UInt64 { lock.lock(); defer { lock.unlock() }; return value }
}

func nativeUnwrappedFieldValue(form: OpenUIString?, name: OpenUIString,
                              read: (OpenUIString) -> Value?) -> Value? {
    let value: Value?
    if let form, case .object(let fields) = read(form) {
        value = fields.last(where: { $0.key == name })?.value
    } else if form == nil { value = read(name) } else { value = nil }
    if case .object(let fields) = value { return fields.last(where: { $0.key == "value" })?.value ?? value }
    return value
}

/// One readiness rule for live action validation and committed UI reads.
/// The caller supplies values from the appropriate ownership boundary.
func nativeActionPlanIsReady(_ plan: ActionPlan, canExecuteActions: Bool,
                             stateValue: (String) -> Value?, queryData: (String) -> Value?,
                             mutationStatus: (String) -> QueryStatus?) -> Bool {
    guard plan.isSourceComplete else { return false }
    if canExecuteActions { return true }
    func ready(_ node: ASTNode) -> Bool {
        var complete = true
        walkAST(node) { node in
            switch node {
            case .ph, .ref: complete = false
            case .stateRef(let name):
                if name != "$value", stateValue(name) == nil { complete = false }
            case .runtimeRef(let name, let type):
                if type == .query, queryData(name) == nil { complete = false }
                if type == .mutation, mutationStatus(name) != .success { complete = false }
            case .runtimeValue(let value):
                if case .undefined = value { complete = false }
            default: break
            }
        }
        return complete
    }
    return plan.steps.allSatisfy { step in
        switch step {
        case .openUrl(let node): return ready(node)
        case .continueConversation(let message, let context): return ready(message) && context.map(ready) != false
        case .set(_, let node): return ready(node)
        case .reset: return true
        case .custom(_, let args): return args.allSatisfy { ready($0.1) }
        case .run: return canExecuteActions
        }
    }
}

private func nativePresentationErrorsEqual(_ lhs: [OpenUIError], _ rhs: [OpenUIError]) -> Bool {
    func same(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case (.none, .none): return true
        case (.some(let a), .some(let b)): return a.utf16.elementsEqual(b.utf16)
        default: return false
        }
    }
    return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { a, b in
        a.source == b.source && a.code == b.code && same(a.message, b.message)
            && same(a.statementId, b.statementId) && same(a.component, b.component)
            && a.path == b.path && a.toolName == b.toolName && same(a.hint, b.hint) && same(a.severity, b.severity)
    }
}
