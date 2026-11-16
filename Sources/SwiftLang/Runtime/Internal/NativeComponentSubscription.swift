import Combine

/// One mounted component's immutable read model. It contains no writable Store
/// and does not participate in language evaluation or action execution.
struct NativeComponentPresentation {
    let element: EvaluatedElement
    let ready: Bool
    let sourceRevision: Int
    let presentationRevision: Int
    let streaming: Bool
    let queryLoading: Bool
    let pendingData: Bool
    let failedData: Bool
    let interruptedData: Bool

    @MainActor static func capture(_ source: EvaluatedElement, state: OpenUIState) -> Self {
        let commit = state.nativePresentation
        let element = state.nativeLiveElement(matching: source)
        let queries = element.sourceReadiness.queryDependencies.map { commit.queryStates[$0.displayString] }
        return Self(element: element, ready: state.nativeIsElementReady(element),
            sourceRevision: commit.sourceRevision, presentationRevision: commit.presentationRevision,
            streaming: !commit.isComplete, queryLoading: commit.isQueryLoading,
            pendingData: queries.contains { $0?.status == .loading || (!commit.isComplete && ($0 == nil || $0?.status == .idle)) },
            failedData: queries.contains { $0?.status == .error },
            interruptedData: commit.isInterrupted && queries.contains { $0 == nil || $0?.status == .idle })
    }

    func hasSameInputs(as other: Self) -> Bool {
        ready == other.ready && sourceRevision == other.sourceRevision
            && presentationRevision == other.presentationRevision
            && streaming == other.streaming && queryLoading == other.queryLoading
            && pendingData == other.pendingData && failedData == other.failedData
            && interruptedData == other.interruptedData
            && nativePresentationInputsEqual(element, other.element)
    }
}

private enum NativeComponentReadKey: Hashable {
    case field(form: OpenUIString?, name: OpenUIString)
    case state(OpenUIString)
}

private struct NativeComponentRead {
    // Optional is intentional: an absent field and a stored undefined value
    // have different fallback behavior, even when the same name is read twice.
    var value: Value?
}

/// Retained by a single mounted Host through StateObject. Its registration is
/// weak, and dependencies are read-only observations of the authoritative State.
@MainActor
final class NativeComponentSubscription: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private weak var state: OpenUIState?
    private weak var updates: NativeComponentUpdates?
    private var source: EvaluatedElement?
    private var presentation: NativeComponentPresentation?
    private var storeRevision: UInt64 = 0
    private var canExecuteActions = false
    private var isRuntimeLimited = false
    private var reads: [NativeComponentReadKey: NativeComponentRead] = [:]
    private var generation: UInt64 = 0
    private(set) var revision: UInt64 = 0

    /// Called only when SwiftUI actually evaluates the component boundary.
    /// Recording dependencies does not publish, parse, or change business state.
    func begin(element: EvaluatedElement, state: OpenUIState) -> (NativeComponentPresentation, NativeComponentReadScope) {
        if self.state !== state {
            updates?.detach(self)
            self.state = state
            updates = state.componentUpdates
            state.componentUpdates.attach(self)
        }
        source = element
        let current = NativeComponentPresentation.capture(element, state: state)
        presentation = current
        storeRevision = state.nativePresentation.storeRevision
        canExecuteActions = state.nativePresentation.canExecuteActions
        isRuntimeLimited = state.nativePresentation.isRuntimeLimited
        generation &+= 1
        reads.removeAll(keepingCapacity: true)
        return (current, NativeComponentReadScope(subscription: self, generation: generation, revision: revision))
    }

    func refresh(state: OpenUIState, changes: NativeLiveElementIndex.Update, auxiliaryChanged: Bool) {
        guard self.state === state, let source, let previous = presentation else { return }
        let commit = state.nativePresentation
        let storeChanged = storeRevision != commit.storeRevision
        let executionChanged = canExecuteActions != commit.canExecuteActions || isRuntimeLimited != commit.isRuntimeLimited
        let sourceChanged = previous.sourceRevision != commit.sourceRevision
        // An unchanged candidate bucket needs no live lookup or action walk.
        // Document/Store/Query changes independently invalidate those derived
        // inputs, including a direct-mounted old snapshot losing membership.
        guard auxiliaryChanged || storeChanged || executionChanged || changes.affectsLookup(for: source)
            || previous.streaming != (commit.isComplete == false) || previous.queryLoading != commit.isQueryLoading
            || sourceChanged
            || previous.presentationRevision != commit.presentationRevision else { return }
        if sourceChanged {
            // Retire the old scope at commit, before SwiftUI has had a chance
            // to render again. Retained getters still return committed values,
            // but cannot subscribe the new document to an old view's fields.
            generation &+= 1
            reads.removeAll(keepingCapacity: true)
        }
        let current = NativeComponentPresentation.capture(source, state: state)
        let valuesChanged = (auxiliaryChanged || storeChanged) && refreshReads(state: state)
        presentation = current
        storeRevision = commit.storeRevision
        canExecuteActions = commit.canExecuteActions
        isRuntimeLimited = commit.isRuntimeLimited
        guard !previous.hasSameInputs(as: current) || valuesChanged else { return }
        revision &+= 1
        objectWillChange.send()
    }

    fileprivate func recordField(form: OpenUIString?, name: OpenUIString, value: Value?, generation: UInt64) {
        guard self.generation == generation else { return }
        reads[.field(form: form, name: name)] = NativeComponentRead(value: value)
    }

    fileprivate func recordState(_ name: OpenUIString, value: Value, generation: UInt64) {
        guard self.generation == generation else { return }
        reads[.state(name)] = NativeComponentRead(value: value)
    }

    private func refreshReads(state: OpenUIState) -> Bool {
        var changed = false
        for (key, previous) in reads {
            let current: Value?
            switch key {
            case .field(let form, let name): current = state.nativePresentedFieldValue(form: form, name: name)
            case .state(let name): current = state.nativePresentedStateValue(name)
            }
            if !sameRead(previous.value, current) { changed = true }
            reads[key] = NativeComponentRead(value: current)
        }
        return changed
    }

    private func sameRead(_ left: Value?, _ right: Value?) -> Bool {
        switch (left, right) {
        case (.none, .none): return true
        case (.some(let left), .some(let right)):
            // Use the same reference-sensitive native boundary as component
            // props. Equal business contents may carry new readiness metadata.
            return nativePresentationValuesEqual(left, right)
        default: return false
        }
    }
}

/// Child bodies and Binding getters may execute after their Host. A scope keeps
/// those reads associated with that render; old retained callbacks cannot add
/// dependencies to a later render or a replacement document.
@MainActor
final class NativeComponentReadScope {
    private weak var subscription: NativeComponentSubscription?
    private let generation: UInt64
    let revision: UInt64

    fileprivate init(subscription: NativeComponentSubscription, generation: UInt64, revision: UInt64) {
        self.subscription = subscription; self.generation = generation; self.revision = revision
    }

    func field(form: OpenUIString?, name: OpenUIString, value: Value?) {
        subscription?.recordField(form: form, name: name, value: value, generation: generation)
    }

    func state(_ name: String, value: Value) {
        subscription?.recordState(OpenUIString(name), value: value, generation: generation)
    }
}
