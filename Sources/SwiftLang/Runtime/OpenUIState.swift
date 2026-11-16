// Shared SwiftUI session ownership around the OpenUI language runtime.
// Component libraries supply schemas and presentation; this state owns one
// stream, Store, action/query lifecycle, and presentation-scoped resources.
import SwiftUI
import Combine

/// Optional diagnostic evidence from the real action evaluation, before its
/// result is written. Observing this does not evaluate an expression twice.
public struct OpenUIActionEvaluation {
    public let sourceRevision: Int
    public let expression: ASTNode
    public let state: [OpenUIString: Value]
    public let result: Value
}

@MainActor
public final class OpenUIState: ObservableObject {
    @Published public private(set) var root: EvaluatedElement?
    // Readiness is committed with root below. Publishing this companion first
    // used to invalidate every observer twice for a single streamed prefix.
    package private(set) var presentationRoot: NativeSourceReadiness?
    @Published public private(set) var errors: [OpenUIError] = []
    @Published public private(set) var isComplete = false {
        didSet { if isComplete != oldValue { componentUpdates.invalidate() } }
    }
    @Published public private(set) var isInterrupted = false {
        didSet { if isInterrupted != oldValue { componentUpdates.invalidate() } }
    }
    @Published public private(set) var queryStates: [String: QueryState] = [:] {
        didSet { if !nativeQueryStatesEqual(oldValue, queryStates) { componentUpdates.invalidate() } }
    }
    @Published public private(set) var mutationStates: [String: MutationState] = [:] {
        didSet { if !nativeMutationStatesEqual(oldValue, mutationStates) { componentUpdates.invalidate() } }
    }
    /// Matches the reference context's loading signal, including declared
    /// Queries waiting for their streamed program to become executable.
    public var isQueryLoading: Bool {
        queryStates.values.contains { $0.status == .loading }
            || (!isComplete && !(latestResult?.queryStatements.isEmpty ?? true))
    }
    public var onAction: ((ActionEvent) -> Void)?
    public var onParseResult: ((ParseResult) -> Void)?
    public var onError: (([OpenUIError]) -> Void)?
    /// Replacing source invalidates callbacks belonging to an older UI tree.
    public var sourceRevision: Int { streamGeneration }
    /// Native presentation identity changes only when the program is replaced.
    /// Appended chunks, state writes, query results and patches keep local UI.
    public private(set) var presentationRevision = 0
    private var errorRevision: [String]?
    public var onStateUpdate: (([OpenUIString: Value]) -> Void)?
    public var onActionEvaluation: ((OpenUIActionEvaluation) -> Void)?

    private var parser: StreamParser
    private var store: Store
    private var unsubscribeStore: (() -> Void)?
    let componentUpdates = NativeComponentUpdates()
    let presentationStore = NativePresentationStore()
    var nativePresentation: NativePresentationCommit { presentationStore.snapshot }
    private let nativeStoreChanges = NativeStoreRevision()
    private var nativeStoreReadVersion: UInt64 = 0
    private var nativeStoreSnapshotRevision: UInt64 = 0
    private var nativeStoreValues: [OpenUIString: Value] = [:]
    private var nativeStoreHasSourceMetadata = false
    private var queryManager: QueryManager
    private let schema: LibrarySchema
    private let functions: [String: CustomFunction]
    private let toolProvider: ToolProvider?
    private var latestResult: ParseResult?
    /// Stream termination alone does not make a truncated preview executable.
    /// Recoverable rendering diagnostics remain local to their components.
    package var canExecuteActions: Bool {
        guard isComplete, !isInterrupted, let result = latestResult else { return false }
        return !result.nativeLimitExceeded && !result.meta.incomplete && result.meta.unresolved.isEmpty
    }
    private var liveElements = NativeLiveElementIndex()
    private var indexedRoot: EvaluatedElement?
    private var pendingIndexChanges = NativeLiveElementIndex.Update()
    private var liveElementCache: [ObjectIdentifier: (snapshot: EvaluatedElement, current: EvaluatedElement)] = [:]
    package func liveElement(matching element: EvaluatedElement) -> EvaluatedElement {
        // Preserve public willSet reads: an observer still holding the public
        // root must not borrow a candidate root's membership before assignment.
        guard let root, root !== element else { return element }
        if liveElements.contains(element) { return element }
        let key = ObjectIdentifier(element)
        if let cached = liveElementCache[key], cached.snapshot === element { return cached.current }
        let current = nativeResolveLiveElement(element, in: liveElements)
        liveElementCache[key] = (element, current)
        return current
    }

    func nativeLiveElement(matching element: EvaluatedElement) -> EvaluatedElement {
        let commit = nativePresentation
        if commit.root === indexedRoot { return liveElement(matching: element) }
        return commit.resolve(element)
    }

    func nativeIsElementReady(_ snapshot: EvaluatedElement) -> Bool {
        let commit = nativePresentation
        let element = nativeLiveElement(matching: snapshot)
        let present = commit.root === indexedRoot ? liveElements.contains(element) : commit.contains(element)
        guard present, !commit.isRuntimeLimited, element.isSourceComplete else { return false }
        func ready(_ value: Value) -> Bool {
            switch value {
            case .actionPlan(let plan): return commit.isPlanReady(plan)
            case .array(let values): return values.allSatisfy(ready)
            case .object(let fields): return fields.allSatisfy { ready($0.value) }
            default: return true
            }
        }
        return element.props.allSatisfy { ready($0.1) }
    }
    private func indexLiveElements(_ root: EvaluatedElement?) {
        liveElementCache.removeAll(keepingCapacity: true)
        pendingIndexChanges.formUnion(liveElements.replaceRoot(root))
        indexedRoot = root
    }
    package func isElementCurrent(_ snapshot: EvaluatedElement) -> Bool {
        liveElements.contains(liveElement(matching: snapshot))
    }
    package func isElementReady(_ snapshot: EvaluatedElement) -> Bool {
        // A closed component may still contain an older, incomplete action
        // snapshot. Membership in the current projection, not the component's
        // own delimiter, determines whether its nested metadata is current.
        // A removed component cannot keep acting on its old complete snapshot.
        let element = liveElement(matching: snapshot)
        guard liveElements.contains(element), let result = latestResult,
              !result.nativeLimitExceeded, element.isSourceComplete else { return false }
        func ready(_ value: Value) -> Bool {
            switch value {
            case .actionPlan(let plan): return isPlanReady(plan)
            case .array(let values): return values.allSatisfy(ready)
            case .object(let fields): return fields.allSatisfy { ready($0.value) }
            default: return true
            }
        }
        return element.props.allSatisfy { ready($0.1) }
    }
    package func isPlanReady(_ plan: ActionPlan) -> Bool {
        guard latestResult?.nativeLimitExceeded != true else { return false }
        return nativeActionPlanIsReady(plan, canExecuteActions: canExecuteActions,
            stateValue: { self.store.get(OpenUIString($0)) },
            queryData: { self.queryManager.queryState(for: $0)?.data },
            mutationStatus: { self.queryManager.mutationState(for: $0)?.status })
    }
    private var streamGeneration = 0 {
        didSet { componentUpdates.invalidate() }
    }
    private var persistedState: [OpenUIString: Value]
    private var unsubscribe: (() -> Void)?
    private var queryDelivery: NativeQueryUpdateDelivery?
    private var source = ""
    private var querySourceGeneration = -1
    private var queryStoreSnapshot: [OpenUIString: Value] = [:]
    private var idleMutations: [String: Value] = [:]
    // @Published delivers synchronously from willSet. A host may request a
    // new source/state from that callback; run it after the current setter
    // finishes so the old assignment cannot overwrite the newer document.
    private var mutationSequence = 0
    private var activeMutation = 0
    private var drainingMutations = false
    private var queuedMutations: ArraySlice<() -> Void> = []
    private var activeSourceRequest: (text: String, streaming: Bool)?
    private var finishingSource = false
    private func mutate(_ body: @escaping () -> Void) {
        mutationSequence &+= 1
        queuedMutations.append(body)
        guard !drainingMutations else { return }
        drainingMutations = true
        defer {
            queuedMutations.removeAll()
            drainingMutations = false
        }
        repeat {
            while let next = queuedMutations.popFirst() {
                // Already queued work runs in FIFO order. Only a new request
                // made during this operation supersedes its publication.
                activeMutation = mutationSequence
                next()
            }
            // Native UI receives one coherent read model after semantic work
            // and public callbacks settle. Keep the queue protected while both
            // native publishers deliver: a reentrant write must run after the
            // current setter, rather than be overwritten when it returns.
            commitNativePresentation()
            if !queuedMutations.isEmpty { continue }
            let changes = pendingIndexChanges
            pendingIndexChanges = NativeLiveElementIndex.Update()
            componentUpdates.flush(state: self, changes: changes)
        } while !queuedMutations.isEmpty
    }

    private func commitNativePresentation() {
        let storeVersion = nativeStoreChanges.read()
        if nativeStoreReadVersion != storeVersion || nativeStoreHasSourceMetadata {
            nativeStoreValues = store.getSnapshot()
            nativeStoreReadVersion = storeVersion
            nativeStoreHasSourceMetadata = nativeStoreValues.values.contains { $0.containsSourceMetadata }
            nativeStoreSnapshotRevision &+= 1
        }
        let commit = NativePresentationCommit(root: root, presentationRoot: presentationRoot,
            sourceRevision: sourceRevision, presentationRevision: presentationRevision,
            isComplete: isComplete, isInterrupted: isInterrupted, isQueryLoading: isQueryLoading,
            canExecuteActions: canExecuteActions, isRuntimeLimited: latestResult?.nativeLimitExceeded == true,
            queryStates: queryStates, mutationStates: mutationStates, errors: errors,
            storeValues: nativeStoreValues, storeRevision: nativeStoreSnapshotRevision)
        NativeRuntimeTrace.measure("Presentation commit") { presentationStore.commit(commit) }
    }
    private var mutationIsCurrent: Bool { activeMutation == mutationSequence }
    package let mediaCache = NativeMediaCache()
    package let resourceStore = NativeResourceStore()
    // Unrepresentable edits may outlive a mounted view. These records are not
    // another committed Store and never appear in actions or serialization.
    private struct EditingKey: Hashable { let kind: String; let form: OpenUIString?; let name: OpenUIString }
    private var editingRecords: [EditingKey: AnyObject] = [:]
    package func editingRecord<T: AnyObject>(kind: String, form: OpenUIString?, name: OpenUIString,
                                     create: () -> T) -> T {
        let key = EditingKey(kind: kind, form: form, name: name)
        if let record = editingRecords[key] as? T { return record }
        let record = create(); editingRecords[key] = record; return record
    }
    package func existingEditingRecord<T: AnyObject>(kind: String, form: OpenUIString?, name: OpenUIString) -> T? {
        editingRecords[EditingKey(kind: kind, form: form, name: name)] as? T
    }


    public init(schema: LibrarySchema, functions: [String: CustomFunction] = [:],
                toolProvider: ToolProvider? = nil, persistedState: [OpenUIString: Value] = [:]) {
        self.toolProvider = toolProvider; self.persistedState = persistedState
        self.schema = schema; self.functions = functions
        parser = createStreamingParser(schema: schema); store = createStore()
        queryManager = QueryManager(provider: toolProvider)
        observeStore()
        observeQueries()
    }

    deinit {
        unsubscribeStore?()
        unsubscribe?(); queryManager.dispose()
        // In-flight callers can retain the caches beyond this state. Cancel
        // their work when the owning state ends, on the caches' actor.
        let mediaCache = self.mediaCache
        let resourceStore = self.resourceStore
        Task { @MainActor in
            mediaCache.removeAll()
            resourceStore.removeAll()
        }
    }

    private func observeStore() {
        unsubscribeStore?()
        let updates = componentUpdates, changes = nativeStoreChanges
        changes.invalidate()
        unsubscribeStore = store.subscribe { changes.invalidate(); updates.invalidate() }
    }

    private func observeQueries() {
        queryDelivery?.retire()
        let delivery = NativeQueryUpdateDelivery()
        queryDelivery = delivery
        let generation = streamGeneration
        let manager = queryManager
        manager.setNativeLimitHandler { [weak self, weak manager] in
            Task { @MainActor [weak self, weak manager] in
                guard let self, let manager, self.queryManager === manager, manager.nativeLimitExceeded else { return }
                self.stopForRuntimeLimit()
            }
        }
        manager.setAutomaticDispatchCheck { [weak self, weak manager] revalidateRoot in
            await MainActor.run {
                guard let self, let manager, self.queryManager === manager else { return false }
                if revalidateRoot {
                    let epoch = self.streamGeneration
                    self.mutate {
                        guard self.queryManager === manager, self.streamGeneration == epoch,
                              let result = self.latestResult else { return }
                        self.update(from: result, synchronizeQueries: false)
                    }
                }
                // A synchronous callback may have applied a same-manager
                // patch. Its committed root is checked too; the official
                // request-key predicate decides whether this fetch survived.
                return self.queryManager === manager
                    && self.isComplete && !self.isInterrupted && self.latestResult?.nativeLimitExceeded != true
            }
        }
        unsubscribe = queryManager.subscribe { [weak self] in
            guard delivery.enqueue() else { return }
            Task { @MainActor [weak self] in
                guard delivery.take(), let self else { return }
                self.mutate {
                    guard self.streamGeneration == generation, let result = self.latestResult else { return }
                    self.update(from: result, synchronizeQueries: false)
                }
            }
        }
    }

    public func push(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        if queuedMutations.isEmpty && latestResult?.nativeLimitExceeded == true { return }
        mutate { self.pushNow(chunk) }
    }
    private func pushNow(_ chunk: String) {
        guard !chunk.isEmpty, latestResult?.nativeLimitExceeded != true else { return }
        if isComplete { resetNow() }
        let result = parser.push(chunk, complete: false)
        if !result.nativeLimitExceeded { source += chunk }
        acceptSource(result)
    }

    public func complete() {
        if queuedMutations.isEmpty {
            guard !isComplete, !finishingSource, activeSourceRequest?.streaming != false else { return }
        }
        mutate {
            self.finishingSource = true
            defer { self.finishingSource = false }
            self.completeNow()
        }
    }
    private func completeNow() {
        guard !isComplete else { return }
        isComplete = true
        acceptSource(parser.getResult(complete: true))
    }

    /// A host's Stop action ends generation without committing its trailing
    /// token or starting deferred tools. Already completed content is retained.
    /// Use complete() for a normally finished response, not for cancellation.
    public func interrupt() {
        if queuedMutations.isEmpty {
            guard !isComplete, !finishingSource, activeSourceRequest?.streaming != false else { return }
        }
        mutate {
            self.finishingSource = true
            defer { self.finishingSource = false }
            self.interruptNow()
        }
    }
    private func interruptNow() {
        guard !isComplete else { return }
        isInterrupted = true
        isComplete = true
        acceptSource(parser.getResult(complete: false))
    }

    public func reset() {
        mutate { self.resetNow() }
    }
    private func resetNow() {
        let hadErrors = !errors.isEmpty
        streamGeneration += 1
        mediaCache.removeAll()
        resourceStore.removeAll()
        editingRecords.removeAll()
        presentationRevision += 1
        unsubscribe?(); queryManager.dispose()
        queryManager = QueryManager(provider: toolProvider)
        parser = createStreamingParser(schema: schema); store = createStore()
        observeStore()
        latestResult = nil; source = ""; persistedState = [:]
        indexLiveElements(nil)
        querySourceGeneration = -1; queryStoreSnapshot = [:]; idleMutations = [:]
        presentationRoot = nil; root = nil; errors = []; queryStates = [:]; mutationStates = [:]; isComplete = false; isInterrupted = false
        errorRevision = nil
        observeQueries()
        if hadErrors && mutationIsCurrent { onError?([]) }
    }

    /// Host-owned full-response and editing surfaces can retain user state.
    public func setSource(_ text: String, streaming: Bool = false) {
        if queuedMutations.isEmpty, let activeSourceRequest,
           activeSourceRequest.streaming == streaming, activeSourceRequest.text.utf16.elementsEqual(text.utf16) { return }
        if queuedMutations.isEmpty, !isInterrupted, source.utf16.elementsEqual(text.utf16) {
            if streaming && !isComplete && latestResult != nil { return }
            if !streaming && isComplete { return }
        }
        mutate {
            self.activeSourceRequest = (text, streaming)
            defer { self.activeSourceRequest = nil }
            self.setSourceNow(text, streaming: streaming)
        }
    }
    private func setSourceNow(_ text: String, streaming: Bool) {
        guard OpenUIRuntimeBudget.acceptsSource(text) else {
            acceptSource(parser.set(text, complete: !streaming)); return
        }
        // Hosting updates may replay the same full buffer. Compare UTF-16,
        // not Swift's canonically equivalent String equality: the runtime
        // preserves distinct code-unit spellings in literals and state keys.
        if !isInterrupted, source.utf16.elementsEqual(text.utf16) {
            if !streaming {
                // An unchanged final snapshot must still commit the trailing
                // token and enable completed actions exactly once.
                completeNow()
                return
            }
            if !isComplete, latestResult != nil {
                // A repeated in-flight snapshot changes neither content nor
                // readiness. Do not reparse, publish, or advance callback IDs.
                return
            }
        }
        // Full-buffer streaming is also supported: a growing UTF-16 prefix is
        // the same presentation, including its final completion snapshot.
        let extendsStream = !isComplete && !source.isEmpty && text.utf16.starts(with: source.utf16)
        if extendsStream {
            // A full-buffer streaming host is delivering only a new suffix.
            // Keep the same document epoch, query subscriptions, and user drafts.
            // The shared streaming parser already owns completed-prefix reuse.
            let boundary = String.Index(utf16Offset: source.utf16.count, in: text)
            let suffix = String(text[boundary...])
            if !suffix.isEmpty {
                source = text
                if !streaming { isComplete = true }
                acceptSource(parser.push(suffix, complete: !streaming))
            }
            return
        }
        replaceSource(text, streaming: streaming, replacesPresentation: !extendsStream)
    }

    private func replaceSource(_ text: String, streaming: Bool, replacesPresentation: Bool) {
        streamGeneration += 1
        unsubscribe?()
        if replacesPresentation {
            presentationRevision += 1; mediaCache.removeAll(); resourceStore.removeAll(); editingRecords.removeAll()
            // A retired document must not launch new downstream queries when
            // an old upstream fetch settles during the replacement's stream.
            queryManager.dispose()
            queryManager = QueryManager(provider: toolProvider)
            querySourceGeneration = -1; queryStoreSnapshot = [:]
        } else {
            queryManager.invalidateMutations()
        }
        idleMutations = [:]
        observeQueries()
        source = text; isComplete = !streaming; isInterrupted = false
        acceptSource(parser.set(text, complete: !streaming))
    }

    /// A patch is merged only once its stream is finished.
    public func applyPatch(_ patch: String) {
        if queuedMutations.isEmpty && !isComplete { return }
        mutate {
            guard self.isComplete else { return }
            do {
                let merged = try mergeStatements(self.source, patch)
                self.replaceSource(merged, streaming: false, replacesPresentation: false)
            } catch {
                self.stopForRuntimeLimit()
            }
        }
    }

    public func stateValue(_ name: OpenUIString) -> Value { store.get(name) ?? .null }

    public func setState(_ name: OpenUIString, value: Value) {
        if queuedMutations.isEmpty {
            guard let result = latestResult, !result.nativeLimitExceeded else { return }
        }
        mutate { self.setStateNow(name, value: value) }
    }
    private func setStateNow(_ name: OpenUIString, value: Value) {
        guard let result = latestResult, !result.nativeLimitExceeded else { return }
        store.set(name, value: value, pristine: false)
        guard !store.nativeLimitExceeded else { stopForRuntimeLimit(); return }
        update(from: result)
        if mutationIsCurrent { onStateUpdate?(store.getSnapshot()) }
    }

    public func snapshotState() -> [OpenUIString: Value] { store.getSnapshot() }

    public func restoreState(_ values: [OpenUIString: Value]) {
        mutate {
            self.persistedState = values
            if let result = self.latestResult { self.update(from: result) }
        }
    }

    /// Components keep native Binding ownership while writing through this runtime.
    public func binding(for name: String) -> Binding<Value> {
        binding(for: name, expectedSourceRevision: nil)
    }
    private func acceptsWrite(expectedSourceRevision: Int?, source: EvaluatedElement?, presentation: Bool = false) -> Bool {
        guard expectedSourceRevision == nil || streamGeneration == expectedSourceRevision else { return false }
        guard let source else { return true }
        return presentation ? isElementCurrent(source) : isElementReady(source)
    }
    private func binding(for name: String, expectedSourceRevision: Int?, source: EvaluatedElement? = nil,
                         presentation: Bool = false) -> Binding<Value> {
        Binding(get: { [weak self] in self?.stateValue(name) ?? .null },
                set: { [weak self] value in
                    guard let self, self.acceptsWrite(expectedSourceRevision: expectedSourceRevision,
                        source: source, presentation: presentation) else { return }
                    if self.queuedMutations.isEmpty && self.latestResult?.nativeLimitExceeded != false { return }
                    self.mutate {
                        guard self.acceptsWrite(expectedSourceRevision: expectedSourceRevision,
                            source: source, presentation: presentation) else { return }
                        self.setStateNow(OpenUIString(name), value: value)
                    }
                })
    }

    public func binding(for element: EvaluatedElement, prop: String) -> Binding<Value>? {
        binding(for: element, prop: prop, expectedSourceRevision: nil)
    }
    package func binding(for element: EvaluatedElement, prop: String, expectedSourceRevision: Int?,
                         presentation: Bool = false) -> Binding<Value>? {
        guard let value = element.props.last(where: { $0.0 == prop })?.1 else { return nil }
        // The revision-bearing overload belongs to a component callback. Public
        // Host bindings remain independent of the current rendered controls.
        let source = expectedSourceRevision == nil ? nil : element
        if case .binding(let assignment) = value {
            return binding(for: assignment.target, expectedSourceRevision: expectedSourceRevision,
                           source: source, presentation: presentation)
        }
        if case .reactiveBinding(let assignment) = value {
            let target = assignment.target, expression = assignment.expression
            return Binding(get: { [weak self] in self?.stateValue(target) ?? .null }, set: { [weak self] newValue in
                guard let self, self.acceptsWrite(expectedSourceRevision: expectedSourceRevision,
                    source: source, presentation: presentation) else { return }
                if self.queuedMutations.isEmpty && self.latestResult?.nativeLimitExceeded != false { return }
                self.mutate {
                    guard self.acceptsWrite(expectedSourceRevision: expectedSourceRevision,
                              source: source, presentation: presentation),
                          let result = self.latestResult, !result.nativeLimitExceeded else { return }
                    let evaluator = self.makeEvaluator(result: result, extraScope: ["$value": newValue])
                    let value = evaluator.evaluate(expression)
                    guard self.mutationIsCurrent else { return }
                    guard !evaluator.nativeLimitExceeded else { self.stopForRuntimeLimit(); return }
                    self.setStateNow(OpenUIString(target), value: value)
                }
            })
        }
        return nil
    }

    public func fieldValue(form: OpenUIString?, name: OpenUIString, fallback: Value = .null) -> Value {
        nativeFieldValue(form: form, name: name) ?? fallback
    }

    func nativeFieldValue(form: OpenUIString?, name: OpenUIString) -> Value? {
        nativeUnwrappedFieldValue(form: form, name: name, read: { self.store.get($0) })
    }

    func nativePresentedFieldValue(form: OpenUIString?, name: OpenUIString) -> Value? {
        nativePresentation.fieldValue(form: form, name: name)
    }

    func nativePresentedStateValue(_ name: OpenUIString) -> Value {
        nativePresentation.storeValues[name] ?? .null
    }

    public func setFieldValue(form: OpenUIString?, name: OpenUIString, value: Value, componentType: String? = "input") {
        enqueueFieldValue(form: form, name: name, value: value, componentType: componentType, expectedSourceRevision: nil)
    }
    package func setFieldValue(form: OpenUIString?, name: OpenUIString, value: Value,
                               componentType: String?, expectedSourceRevision: Int,
                               source: EvaluatedElement? = nil, presentation: Bool = false) {
        enqueueFieldValue(form: form, name: name, value: value, componentType: componentType,
                          expectedSourceRevision: expectedSourceRevision, source: source, presentation: presentation)
    }
    private func enqueueFieldValue(form: OpenUIString?, name: OpenUIString, value: Value,
                                   componentType: String?, expectedSourceRevision: Int?,
                                   source: EvaluatedElement? = nil, presentation: Bool = false) {
        guard acceptsWrite(expectedSourceRevision: expectedSourceRevision, source: source, presentation: presentation) else { return }
        if queuedMutations.isEmpty {
            guard let result = latestResult, !result.nativeLimitExceeded else { return }
        }
        mutate {
            guard self.acceptsWrite(expectedSourceRevision: expectedSourceRevision,
                source: source, presentation: presentation) else { return }
            self.setFieldValueNow(form: form, name: name, value: value, componentType: componentType)
        }
    }
    private func setFieldValueNow(form: OpenUIString?, name: OpenUIString, value: Value, componentType: String?) {
        var properties = [ObjectField(key: "value", value: value)]
        if let componentType { properties.append(ObjectField(key: "componentType", value: .string(componentType))) }
        let wrapped = Value.object(properties)
        if let form {
            var fields: [ObjectField] = []
            if case .object(let current) = store.get(form) { fields = Array(current) }
            fields.removeAll { $0.key == name }; fields.append(ObjectField(key: name, value: wrapped))
            setStateNow(form, value: .object(fields))
        } else { setStateNow(name, value: wrapped) }
    }

    /// Call when an application field mounts. Persisted/user-entered values
    /// win over the component's initial value.
    public func initializeField(form: OpenUIString?, name: OpenUIString, value: Value, componentType: String = "input") {
        enqueueInitialField(form: form, name: name, value: value, componentType: componentType, expectedSourceRevision: nil)
    }
    package func initializeField(form: OpenUIString?, name: OpenUIString, value: Value,
                                 componentType: String, expectedSourceRevision: Int, source: EvaluatedElement? = nil) {
        enqueueInitialField(form: form, name: name, value: value, componentType: componentType,
                            expectedSourceRevision: expectedSourceRevision, source: source)
    }
    private func enqueueInitialField(form: OpenUIString?, name: OpenUIString, value: Value,
                                     componentType: String, expectedSourceRevision: Int?, source: EvaluatedElement? = nil) {
        guard acceptsWrite(expectedSourceRevision: expectedSourceRevision, source: source) else { return }
        if queuedMutations.isEmpty {
            guard !hasField(form: form, name: name), let result = latestResult, !result.nativeLimitExceeded else { return }
        }
        mutate {
            guard self.acceptsWrite(expectedSourceRevision: expectedSourceRevision, source: source) else { return }
            self.initializeFieldNow(form: form, name: name, value: value, componentType: componentType)
        }
    }
    private func initializeFieldNow(form: OpenUIString?, name: OpenUIString, value: Value, componentType: String) {
        guard !hasField(form: form, name: name) else { return }
        setFieldValueNow(form: form, name: name, value: value, componentType: componentType)
    }
    private func hasField(form: OpenUIString?, name: OpenUIString) -> Bool {
        let existing: Value?
        if let form, case .object(let fields) = store.get(form) { existing = fields.last(where: { $0.key == name })?.value }
        else if form == nil { existing = store.get(name) } else { existing = nil }
        return existing != nil
    }

    public func fieldBinding(form: OpenUIString?, name: OpenUIString, fallback: Value = .null, componentType: String = "input") -> Binding<Value> {
        fieldBinding(form: form, name: name, fallback: fallback, componentType: componentType, expectedSourceRevision: nil)
    }
    package func fieldBinding(form: OpenUIString?, name: OpenUIString, fallback: Value,
                              componentType: String, expectedSourceRevision: Int?, source: EvaluatedElement? = nil) -> Binding<Value> {
        Binding(get: { [weak self] in self?.fieldValue(form: form, name: name, fallback: fallback) ?? fallback },
                set: { [weak self] in self?.enqueueFieldValue(form: form, name: name, value: $0,
                    componentType: componentType, expectedSourceRevision: expectedSourceRevision, source: source) })
    }

    private func formPayload(_ name: OpenUIString?) -> [(OpenUIString, Value)] {
        if let name, let value = store.get(name) { return [(name, value)] }
        return store.getSnapshot().sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// Button dispatch including the legacy action-object wire shape. JSON
    /// objects cannot impersonate a declared custom action; only @Name calls do.
    public func triggerAction(_ userMessage: String, formName: OpenUIString? = nil, action: Value? = nil) async -> [ActionEvent] {
        await triggerAction(userMessage, formName: formName, action: action, source: nil)
    }
    package func triggerAction(_ userMessage: String, formName: OpenUIString?, action: Value?, source: EvaluatedElement?, onDispatch: ((ActionEvent) -> Void)? = nil) async -> [ActionEvent] {
        guard !Task.isCancelled, source.map(isElementReady) ?? canExecuteActions else { return [] }
        if case .actionPlan(let plan) = action { return await perform(plan, formName: formName, source: source, onDispatch: onDispatch) }
        if case .object(let fields) = action {
            func field(_ key: String) -> Value? { fields.last(where: { $0.key == key })?.value }
            let type: OpenUIString
            if case .string(let name) = field("type"), !name.isEmpty { type = name } else { type = "continue_conversation" }
            guard schema.callDefs[type.displayString].map({ $0.kind == .action && !$0.isBuiltin }) != true else { return [] }
            var params: [ObjectField] = []
            if case .object(let values) = field("params") { params = Array(values) }
            for key in ["url", "context"] {
                if let value = field(key), isTruthy(value) {
                    params.removeAll { $0.key == key }; params.append(.init(key: key, value: value))
                }
            }
            let event = ActionEvent(type: type, params: params.map { ($0.key, $0.value) }, humanFriendlyMessage: OpenUIString(userMessage),
                                    formState: formPayload(formName), formName: formName)
            onDispatch?(event); onAction?(event); return [event]
        }
        guard action == nil || action == .null else { return [] }
        return await perform(ActionPlan(steps: [.continueConversation(messageAST: .str(userMessage), contextAST: nil)]), formName: formName, source: source, onDispatch: onDispatch)
    }

    /// A retained control can outlive a parser readiness snapshot. Resolve only
    /// the same action in the same live source before checking or dispatching it.
    package func currentActionPlan(_ plan: ActionPlan, source: EvaluatedElement?) -> ActionPlan {
        var plan = plan
        if !plan.isSourceComplete, let source {
            let live = liveElement(matching: source)
            func matching(_ value: Value) -> ActionPlan? {
                switch value {
                case .actionPlan(let current): return current == plan && current.isSourceComplete ? current : nil
                case .array(let values): return values.lazy.compactMap(matching).first
                case .object(let fields): return fields.lazy.compactMap { matching($0.value) }.first
                default: return nil
                }
            }
            if live !== source, let refreshed = live.props.lazy.compactMap({ matching($0.1) }).first { plan = refreshed }
        }
        return plan
    }

    public func perform(_ plan: ActionPlan, formName: OpenUIString? = nil) async -> [ActionEvent] {
        await perform(plan, formName: formName, source: nil)
    }
    package func perform(_ plan: ActionPlan, formName: OpenUIString?, source: EvaluatedElement?, onDispatch: ((ActionEvent) -> Void)? = nil) async -> [ActionEvent] {
        let plan = currentActionPlan(plan, source: source)
        guard !Task.isCancelled, source.map(isElementReady) ?? canExecuteActions,
              source == nil || isPlanReady(plan) else { return [] }
        let generation = streamGeneration
        let workBudget = NativeActionWorkBudget()
        let defaults = createStore()
        defaults.initialize(defaults: latestResult!.stateDeclarations, persisted: [:])
        guard !defaults.nativeLimitExceeded else { stopForRuntimeLimit(); return [] }
        var context = ActionRuntimeContext(
            store: store,
            evaluate: { [weak self] node in
                guard let self, self.streamGeneration == generation,
                      let result = self.latestResult, !result.nativeLimitExceeded else { return .null }
                let snapshot = self.onActionEvaluation == nil ? [:] : self.store.getSnapshot()
                let evaluator = self.makeEvaluator(result: result, workBudget: workBudget)
                let value = evaluator.evaluate(node)
                guard !evaluator.nativeLimitExceeded else { self.stopForRuntimeLimit(); return .null }
                self.onActionEvaluation?(OpenUIActionEvaluation(sourceRevision: generation,
                    expression: node, state: snapshot, result: value))
                return value
            },
            stateDefaults: defaults.getSnapshot(),
            runQuery: { [weak self] in self?.runDeclaredQuery($0, workBudget: workBudget) },
            runMutation: { [weak self] id in
                guard let self, self.streamGeneration == generation else { return .failure }
                return await self.runDeclaredMutation(id, generation: generation, workBudget: workBudget)
            },
            formState: { [weak self] in self?.formPayload(formName) ?? [] }, formName: formName,
            isActive: { [weak self] in
                self?.streamGeneration == generation && !Task.isCancelled && !workBudget.exceeded
            },
            onStateChange: { [weak self] in
                guard let self else { return }
                self.mutate {
                    guard self.streamGeneration == generation, let result = self.latestResult else { return }
                    guard !self.store.nativeLimitExceeded else { self.stopForRuntimeLimit(); return }
                    self.update(from: result, workBudget: workBudget)
                    if self.mutationIsCurrent { self.onStateUpdate?(self.store.getSnapshot()) }
                }
            },
            onEvent: { [weak self] event in
                guard let self, self.streamGeneration == generation else { return }
                onDispatch?(event)
                self.onAction?(event)
            }
        )
        context.nativeWorkBudget = workBudget
        context.onNativeLimit = { [weak self] in
            guard let self, self.streamGeneration == generation else { return }
            self.stopForRuntimeLimit()
        }
        let events = await runActionPlan(plan, context: context)
        guard streamGeneration == generation else { return [] }
        guard !Task.isCancelled, !workBudget.exceeded else { return events }
        mutate {
            guard self.streamGeneration == generation, let result = self.latestResult else { return }
            self.update(from: result, workBudget: workBudget)
        }
        return streamGeneration == generation ? events : []
    }

    private func runDeclaredQuery(_ id: String, workBudget: NativeActionWorkBudget) {
        // Match the reference adapter: declarations are synchronized by source
        // and Store changes; Run only invalidates the current declaration.
        queryManager.invalidateQuery(statementId: id, workBudget: workBudget)
        if workBudget.exceeded || queryManager.nativeLimitExceeded { stopForRuntimeLimit() }
    }

    private func runDeclaredMutation(_ id: String, generation: Int, workBudget: NativeActionWorkBudget) async -> MutationOutcome {
        guard let result = latestResult, queryManager.mutationState(for: id)?.status != .loading,
              let mutation = result.mutationStatements.first(where: { $0.statementId == id }),
              let toolAST = mutation.toolAST else { return .failure }
        let evaluator = makeEvaluator(result: result, workBudget: workBudget)
        let toolValue = evaluator.evaluate(toolAST)
        guard !evaluator.nativeLimitExceeded else { stopForRuntimeLimit(); return .failure }
        guard case .string(let tool) = toolValue else { return .failure }
        let arguments = mutation.argsAST.map { evaluator.evaluate($0) } ?? .object([])
        guard !evaluator.nativeLimitExceeded else { stopForRuntimeLimit(); return .failure }
        guard !nativeValueExceedsLimits(arguments) else { stopForRuntimeLimit(); return .failure }
        guard !Task.isCancelled, streamGeneration == generation, !workBudget.exceeded else { return .failure }
        let args = transport(arguments)
        let outcome = await queryManager.runMutation(statementId: id, tool: tool, args: args)
        guard !Task.isCancelled, streamGeneration == generation else { return .failure }
        mutate {
            guard self.streamGeneration == generation else { return }
            self.update(from: self.latestResult ?? result, workBudget: workBudget)
        }
        guard !Task.isCancelled, streamGeneration == generation else { return .failure }
        return outcome.status == .success ? .success(outcome.data ?? .null) : .failure
    }

    public func runQuery(statementId: String, tool: OpenUIString, args: Value, defaults: Value = .null) {
        if queuedMutations.isEmpty {
            guard isComplete, !isInterrupted, let result = latestResult, !result.nativeLimitExceeded,
                  result.queryStatements.contains(where: { $0.statementId == statementId }) else { return }
        }
        mutate {
            guard self.isComplete, !self.isInterrupted, let result = self.latestResult, !result.nativeLimitExceeded,
                  result.queryStatements.contains(where: { $0.statementId == statementId }) else { return }
            guard !nativeValueExceedsLimits(args), !nativeValueExceedsLimits(defaults) else {
                self.stopForRuntimeLimit(); return
            }
            self.queryManager.runQuery(statementId: statementId, tool: tool, args: self.transport(args), defaults: defaults)
            self.update(from: result)
        }
    }

    private func transport(_ value: Value) -> Value {
        switch value {
        case .binding(let assignment), .reactiveBinding(let assignment): return store.get(assignment.target) ?? .null
        case .array(let values):
            let next = values.map(transport)
            return zip(values, next).allSatisfy { $0.isSameValue(as: $1) } ? value : .array(next)
        case .object(let fields):
            let next = fields.map { ObjectField(key: $0.key, value: transport($0.value)) }
            return zip(fields, next).allSatisfy { $0.value.isSameValue(as: $1.value) } ? value : .object(next)
        default: return value
        }
    }

    private func makeEvaluator(result: ParseResult, extraScope: [String: Value]? = nil,
                               workBudget: NativeActionWorkBudget? = nil) -> Evaluator {
        final class Box { weak var evaluator: Evaluator!; var resolving = Set<String>(); var defaults: [String: Value] = [:] }
        let box = Box()
        let manager = queryManager
        for mutation in result.mutationStatements where idleMutations[mutation.statementId] == nil {
            idleMutations[mutation.statementId] = MutationState(status: .idle).value
        }
        let idleValues = idleMutations
        let ctx = EvaluationContext(
            getState: { [store] name in store.get(name) ?? .null },
            resolveRef: { [weak manager] name in
                if let state = manager?.queryState(for: name), let data = state.data { return data }
                if let query = result.queryStatements.first(where: { $0.statementId == name }) {
                    if let value = box.defaults[name] { return value }
                    guard box.resolving.insert(name).inserted else { return .null }
                    defer { box.resolving.remove(name) }
                    let value = query.defaultsAST.map { box.evaluator.evaluate($0) } ?? .null
                    box.defaults[name] = value
                    return value
                }
                if result.mutationStatements.contains(where: { $0.statementId == name }) {
                    if let state = manager?.mutationState(for: name) { return state.value }
                    return idleValues[name] ?? .null
                }
                return .null
            }, functions: functions, actions: schema.callDefs.filter { $0.value.kind == .action }, extraScope: extraScope)
        let evaluator = Evaluator(context: ctx, schema: schema)
        evaluator.nativeWorkBudget = workBudget
        let generation = streamGeneration
        // Automatic Query reevaluation may run on a background caller while
        // holding the shared JavaScriptCore lock.
        // The synchronous caller also checks the flag before any side effect;
        // this callback retires a document after an asynchronous failure.
        evaluator.onNativeLimit = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.streamGeneration == generation,
                      self.latestResult?.nativeLimitExceeded != true else { return }
                self.stopForRuntimeLimit()
            }
        }
        box.evaluator = evaluator
        return evaluator
    }

    private func acceptSource(_ result: ParseResult) {
        update(from: result)
        if mutationIsCurrent { onParseResult?(latestResult ?? result) }
    }

    private func stopForRuntimeLimit(preserving previous: ParseResult? = nil) {
        guard drainingMutations else {
            mutate { self.stopForRuntimeLimit(preserving: previous) }
            return
        }
        guard mutationIsCurrent else { return }
        update(from: limitedParseResult(preserving: previous ?? latestResult, error: runtimeBudgetError()))
    }

    private func update(from result: ParseResult, synchronizeQueries: Bool = true,
                        workBudget: NativeActionWorkBudget? = nil) {
        if result.nativeLimitExceeded {
            // A replacement is a new attempt even when the prior document
            // also failed; replaceSource clears isInterrupted for that epoch.
            let firstFailure = latestResult?.nativeLimitExceeded != true || !isInterrupted
            latestResult = result
            if firstFailure {
                streamGeneration += 1
                unsubscribe?(); queryManager.dispose()
                queryManager = QueryManager(provider: toolProvider); observeQueries()
                isInterrupted = true; isComplete = true
                // Keep the last bounded, already projected presentation. Never
                // inspect a failed result's lazy root here: even short input
                // can describe a huge shared graph. All controls are disabled
                // by nativeLimitExceeded until replacement or reset.
                if !queryStates.isEmpty { queryStates = [:] }
                if !mutationStates.isEmpty { mutationStates = [:] }
                errorRevision = nil
                errors = result.meta.errors
                if mutationIsCurrent { onError?(errors) }
            }
            return
        }
        let previous = latestResult
        guard !queryManager.nativeLimitExceeded else { stopForRuntimeLimit(preserving: previous); return }
        latestResult = result
        store.initialize(defaults: result.stateDeclarations, persisted: persistedState)
        persistedState = [:]
        guard !store.nativeLimitExceeded else { stopForRuntimeLimit(preserving: previous); return }
        guard mutationIsCurrent else { return }
        let evaluator = makeEvaluator(result: result, workBudget: workBudget)
        // QueryManager retains this evaluator for later asynchronous reads.
        // Only work performed in this action's current update is charged here.
        defer { evaluator.nativeWorkBudget = nil }
        if isComplete && !isInterrupted {
            let declarations = Dictionary(result.mutationStatements.map { mutation in
            let tool = mutation.toolAST.map { evaluator.evaluate($0) }
            if case .string(let name) = tool { return (mutation.statementId, name) }
            return (mutation.statementId, "")
            }, uniquingKeysWith: { _, new in new })
            guard mutationIsCurrent else { return }
            guard !evaluator.nativeLimitExceeded else { stopForRuntimeLimit(preserving: previous); return }
            queryManager.registerMutations(declarations)
        }
        // Validate dynamic expansion before starting tools. The context uses
        // declared Query defaults until their actual data becomes available.
        var rootReferences: [String: Value] = [:]
        if synchronizeQueries && !result.queryStatements.isEmpty {
            evaluator.onReferenceRead = { rootReferences[$0] = $1 }
        }
        var evaluatedRoot = evaluator.evaluateRoot(result)
        evaluator.onReferenceRead = nil
        guard mutationIsCurrent else { return }
        guard !evaluator.nativeLimitExceeded else { stopForRuntimeLimit(preserving: previous); return }
        var queryValues: [String: QueryState] = [:]
        let executable = queryManager.withDeferredToolDispatch {
            guard mutationIsCurrent else { return false }
            var didSynchronizeQueries = false
            if isComplete && !isInterrupted && synchronizeQueries {
                let sourceChanged = querySourceGeneration != streamGeneration
                querySourceGeneration = streamGeneration
                let snapshot = store.getSnapshot()
                let stateChanged = snapshot.count != queryStoreSnapshot.count || snapshot.contains { queryStoreSnapshot[$0.key]?.isSameValue(as: $0.value) != true }
                queryStoreSnapshot = snapshot
                if sourceChanged || stateChanged {
                    // The official manager owns dependency scheduling and
                    // defaults. Only native provider dispatch is held until
                    // the resulting presentation passes its budget too.
                    queryManager.evaluateStatements(result.queryStatements, evaluator: evaluator)
                    didSynchronizeQueries = true
                }
            }
            guard mutationIsCurrent, !evaluator.nativeLimitExceeded else { return false }
            let currentQueries = queryManager.queryStates(for: result.queryStatements.map(\.statementId))
            for query in result.queryStatements {
                queryValues[query.statementId] = currentQueries[query.statementId]
                    ?? QueryState(status: .idle, data: evaluator.context.resolveRef(query.statementId))
            }
            guard mutationIsCurrent, !evaluator.nativeLimitExceeded else { return false }
            // A changed default must be visible in this synchronous update.
            // Only reevaluate when a reference the root actually read changed.
            if didSynchronizeQueries && rootReferences.contains(where: { name, value in
                guard let current = queryValues[name] else { return false }
                return !(current.data ?? .null).isSameValue(as: value)
            }) {
                evaluatedRoot = evaluator.evaluateRoot(result)
            }
            return mutationIsCurrent && !evaluator.nativeLimitExceeded
        }
        guard mutationIsCurrent else {
            // A reentrant request retired this uncommitted batch. The queued
            // operation will resynchronize its declarations before dispatch.
            if queryManager.isDisposed {
                unsubscribe?()
                queryManager = QueryManager(provider: toolProvider)
                querySourceGeneration = -1; queryStoreSnapshot = [:]; idleMutations = [:]
                observeQueries()
            }
            return
        }
        guard executable else { stopForRuntimeLimit(preserving: previous); return }
        presentationRoot = result.presentationRoot
        guard mutationIsCurrent else { return }
        NativeRuntimeTrace.measure("Live index") { indexLiveElements(evaluatedRoot) }
        root = evaluatedRoot
        guard mutationIsCurrent else { return }
        // Empty auxiliary channels have no changed value to publish. Root and
        // readiness still update above; nonempty values keep their existing
        // delivery semantics, including the transition back to an empty value.
        if !queryValues.isEmpty || !queryStates.isEmpty { queryStates = queryValues }
        guard mutationIsCurrent else { return }
        let mutationValues = Dictionary(uniqueKeysWithValues: result.mutationStatements.map {
            ($0.statementId, queryManager.mutationState(for: $0.statementId) ?? MutationState(status: .idle))
        })
        if !mutationValues.isEmpty || !mutationStates.isEmpty { mutationStates = mutationValues }
        guard mutationIsCurrent else { return }
        let nextErrors = result.meta.errors + (isComplete ? evaluator.errors : [])
            + queryValues.values.compactMap(\.error) + mutationValues.values.compactMap(\.error)
        if !nextErrors.isEmpty || !errors.isEmpty { errors = nextErrors }
        guard mutationIsCurrent else { return }
        let revision = errors.map { error in
            [error.source?.rawValue ?? "", error.code.rawValue, error.statementId ?? "", error.component ?? "",
             error.path.map(jsonStringLiteral) ?? "", error.severity ?? "", error.message].joined(separator: "\u{0}")
        }
        if errorRevision != revision { errorRevision = revision; onError?(errors) }
    }


}
