import SwiftUI

/// Created by the registered component host; all operations use the same runtime.
public struct OpenUIComponentContext {
    public let element: EvaluatedElement
    /// Component-library values are typed extensions, independent of the runtime.
    public var values: OpenUIContextValues
    public let resources: [String: Value]
    public let formName: String?
    public let exactFormName: OpenUIString?
    /// Program transport state. Individual controls use canInteract, which
    /// checks their own source, dependencies and enclosing card/form scope.
    public let isStreaming: Bool
    public let isQueryLoading: Bool
    // EvaluatedElement's equality intentionally follows normative values, not
    // presentation metadata. Copy these snapshots so SwiftUI also invalidates
    // a child when a delimiter or its own query status changes without new data.
    package let presentationReadiness: NativeSourceReadiness
    package let hasPendingData: Bool
    package let hasDataFailure: Bool
    package let hasInterruptedData: Bool
    package var interactionScopeReady = true
    package var activationIntent: NativeActivationIntent?
    package var onUserInteraction: (() -> Void)?
    @MainActor package func recordUserInteraction() { if isCurrentPresentation { onUserInteraction?() } }
    private let state: OpenUIState
    package let registry: OpenUIComponentRegistry
    private let sourceRevision: Int
    // Public, manually constructed contexts have no read scope. Preserve their
    // Store/Query invalidation when passed through child views. Mounted contexts
    // already receive a new read-scope identity for every actual render.
    private let unscopedUpdateRevision: UInt64?
    // Element/phase flags describe this render. Field and Binding getters stay
    // dynamic, but a mounted Context reads only the latest completed native
    // commit, never a Store write halfway through publication. Retaining a
    // Context does not freeze an entire document; action validity remains live.
    private let readScope: NativeComponentReadScope?

    @MainActor public init(element: EvaluatedElement, registry: OpenUIComponentRegistry, state: OpenUIState,
                values: OpenUIContextValues = OpenUIContextValues(), resources: [String: Value] = [:],
                formName: String? = nil, exactFormName: OpenUIString? = nil) {
        self.init(element: element, registry: registry, state: state, values: values, resources: resources,
            formName: formName, exactFormName: exactFormName, nativePresentation: nil, readScope: nil)
    }

    @MainActor init(element: EvaluatedElement, registry: OpenUIComponentRegistry, state: OpenUIState,
                values: OpenUIContextValues, resources: [String: Value],
                formName: String? = nil, exactFormName: OpenUIString? = nil,
                nativePresentation: NativeComponentPresentation?, readScope: NativeComponentReadScope?,
                expectedSourceRevision: Int? = nil) {
        let presentation = nativePresentation ?? (readScope == nil ? nil : NativeComponentPresentation.capture(element, state: state))
        self.element = presentation?.element ?? element; self.registry = registry; self.state = state
        self.values = values; self.resources = resources; self.formName = exactFormName?.displayString ?? formName
        self.exactFormName = exactFormName ?? formName.map { OpenUIString($0) }
        self.readScope = readScope
        self.sourceRevision = expectedSourceRevision ?? presentation?.sourceRevision ?? state.sourceRevision
        self.unscopedUpdateRevision = readScope == nil ? state.componentUpdates.revision : nil
        self.isStreaming = presentation?.streaming ?? !state.isComplete
        self.isQueryLoading = presentation?.queryLoading ?? state.isQueryLoading
        self.presentationReadiness = self.element.sourceReadiness
        if let presentation {
            self.hasPendingData = presentation.pendingData
            self.hasDataFailure = presentation.failedData
            self.hasInterruptedData = presentation.interruptedData
        } else {
            let feedback = nativeQueryDependencyFlags(element.sourceReadiness.queryDependencies,
                isComplete: state.isComplete, isInterrupted: state.isInterrupted,
                status: { state.queryStates[$0.displayString]?.status })
            self.hasPendingData = feedback.pending
            self.hasDataFailure = feedback.failed
            self.hasInterruptedData = feedback.interrupted
        }
    }

    var hasNativeReadScope: Bool { readScope != nil }

    /// Standalone library surfaces can receive a manually created Context.
    /// Observe its owner without rebinding it to an unrelated ambient State,
    /// and retain the original epoch so old event closures remain invalid.
    @MainActor func observing(with subscription: NativeComponentSubscription) -> OpenUIComponentContext {
        let (presentation, reads) = subscription.begin(element: element, state: state,
            expectedSourceRevision: sourceRevision)
        var current = OpenUIComponentContext(element: element, registry: registry, state: state,
            values: values, resources: resources, formName: formName, exactFormName: exactFormName,
            nativePresentation: presentation, readScope: reads, expectedSourceRevision: sourceRevision)
        current.interactionScopeReady = interactionScopeReady
        current.activationIntent = activationIntent
        current.onUserInteraction = onUserInteraction
        return current
    }

    @MainActor public var canInteract: Bool { interactionScopeReady && state.isElementReady(element) && isCurrentPresentation }
    /// Discrete activations also reject the release of a reading/paging drag.
    @MainActor public var canActivate: Bool { canInteract && activationIntent?.permitsActivation != false }
    @MainActor package func canDispatch(_ action: Value?) -> Bool {
        guard canInteract else { return false }
        if case .actionPlan(let plan) = action { return state.isPlanReady(state.currentActionPlan(plan, source: element)) }
        return true
    }
    @MainActor package var isCurrentPresentation: Bool { state.sourceRevision == sourceRevision }
    package var presentationSourceRevision: Int { sourceRevision }
    @MainActor package var presentationRevision: Int {
        readScope == nil ? state.presentationRevision : state.nativePresentation.presentationRevision
    }
    /// Local presentation controls such as Modal close can update their value
    /// while streaming. Epoch checks still reject callbacks from replaced UI.
    @MainActor package func presentationBinding(_ name: String) -> Binding<Value>? {
        guard let binding = state.binding(for: element, prop: name, expectedSourceRevision: sourceRevision,
                                          presentation: true) else { return nil }
        return Binding(get: { readBinding(name, binding: binding) },
            set: { if isCurrentPresentation { binding.wrappedValue = $0 } })
    }
    @MainActor package func presentationFieldValue(_ name: OpenUIString, fallback: Value) -> Value {
        fieldValue(name, fallback: fallback)
    }
    @MainActor package func setPresentationFieldValue(_ name: OpenUIString, value: Value) {
        guard isCurrentPresentation else { return }
        state.setFieldValue(form: exactFormName, name: name, value: value, componentType: nil,
                            expectedSourceRevision: sourceRevision, source: element, presentation: true)
    }
    /// Editing records can be retained by the document. Their callbacks must
    /// not retain the document in return, or releasing a renderer leaks it.
    @MainActor package func weakOperation<Input>(onUnavailable: ((Input) -> Void)? = nil,
        _ body: @escaping (OpenUIComponentContext, Input) -> Void) -> (Input) -> Void {
        let element = element, registry = registry, values = values
        let resources = resources, form = exactFormName, revision = sourceRevision
        let scopeReady = interactionScopeReady
        return { [weak state] value in
            guard let state, state.sourceRevision == revision else { onUnavailable?(value); return }
            var current = OpenUIComponentContext(element: element, registry: registry, state: state,
                values: values, resources: resources, exactFormName: form)
            current.interactionScopeReady = scopeReady
            body(current, value)
        }
    }
    @MainActor package func editingRecord<T: AnyObject>(kind: String, name: OpenUIString, create: () -> T) -> T {
        state.editingRecord(kind: kind, form: exactFormName, name: name, create: create)
    }
    @MainActor package func existingEditingRecord<T: AnyObject>(kind: String, name: OpenUIString) -> T? {
        state.existingEditingRecord(kind: kind, form: exactFormName, name: name)
    }
    @MainActor package func childContext(_ child: EvaluatedElement, form: OpenUIString?) -> OpenUIComponentContext {
        var next = OpenUIComponentContext(element: child, registry: registry, state: state,
            values: values, resources: resources, exactFormName: form,
            nativePresentation: nil, readScope: readScope, expectedSourceRevision: sourceRevision)
        next.interactionScopeReady = interactionScopeReady
        next.activationIntent = activationIntent
        return next
    }
    public func value(_ name: String) -> Value? { element.props.last(where: { $0.0 == name })?.1 }
    /// Geometry/style arguments must not consume an unfinished numeric or enum
    /// token. Data text continues to use value/string for progressive reading.
    package func presentationNumber(_ name: String) -> Double? {
        element.sourceReadiness[name].complete ? number(name) : nil
    }
    package func presentationString(_ name: String) -> String? {
        element.sourceReadiness[name].complete ? string(name) : nil
    }
    /// Native display text. Use codeUnitString/value for semantic action data.
    public func string(_ name: String) -> String? { codeUnitString(name)?.displayString }
    public func codeUnitString(_ name: String) -> OpenUIString? {
        guard case .string(let text) = value(name) else { return nil }; return text
    }
    public func number(_ name: String) -> Double? {
        guard case .number(let number) = value(name), number.isFinite else { return nil }; return number
    }
    public func flag(_ name: String) -> Bool? {
        guard case .boolean(let flag) = value(name) else { return nil }; return flag
    }
    public func resource(_ id: String) -> Value? { resource(OpenUIString(id)) }
    public func resource(_ id: OpenUIString) -> Value? {
        resources.first(where: { OpenUIString($0.key) == id })?.value
    }
    public func slot(_ name: String = "children") -> RenderValue { RenderValue(value(name) ?? .null, registry: registry) }
    public func render(_ value: Value) -> RenderValue { RenderValue(value, registry: registry) }
    public func children(_ name: String = "children") -> [OpenUIRenderChild] {
        OpenUIRenderChild.children(of: value(name) ?? .null, registry: registry)
    }
    @MainActor public func binding(_ name: String) -> Binding<Value>? {
        binding(name, completion: nil)
    }
    /// A write can queue during host publication. Acknowledgment comes from
    /// its existing setter after acceptance, never from a subsequent UI read.
    @MainActor package func binding(_ name: String, completion: ((Value?) -> Void)?) -> Binding<Value>? {
        guard let binding = state.binding(for: element, prop: name, expectedSourceRevision: sourceRevision,
                                          completion: completion) else { return nil }
        return Binding(get: { readBinding(name, binding: binding) },
            set: { if canInteract { binding.wrappedValue = $0 } else { completion?(nil) } })
    }
    @MainActor private func readBinding(_ name: String, binding: Binding<Value>) -> Value {
        switch self.value(name) {
        case .binding(let assignment), .reactiveBinding(let assignment):
            let value = readScope == nil ? binding.wrappedValue : state.nativePresentedStateValue(OpenUIString(assignment.target))
            readScope?.state(assignment.target, value: value)
            return value
        default: return binding.wrappedValue
        }
    }
    public func action(_ name: String = "action") -> ActionPlan? { PropValue.actionPlan(element, name) }

    @MainActor @_disfavoredOverload public func fieldValue<S: StringProtocol>(_ name: S, fallback: Value = .null) -> Value { fieldValue(OpenUIString(String(name)), fallback:fallback) }
    @MainActor public func fieldValue(_ name: OpenUIString, fallback: Value = .null) -> Value {
        fieldValue(form: exactFormName, name: name, fallback: fallback)
    }
    @MainActor package func fieldValue(form: OpenUIString?, name: OpenUIString, fallback: Value = .null) -> Value {
        let value = readScope == nil ? state.nativeFieldValue(form: form, name: name)
            : state.nativePresentedFieldValue(form: form, name: name)
        readScope?.field(form: form, name: name, value: value)
        return value ?? fallback
    }
    @MainActor @_disfavoredOverload public func fieldBinding<S: StringProtocol>(_ name: S, fallback: Value = .null, componentType: String = "input") -> Binding<Value> {
        fieldBinding(OpenUIString(String(name)), fallback:fallback, componentType:componentType)
    }
    @MainActor public func fieldBinding(_ name: OpenUIString, fallback: Value = .null, componentType: String = "input") -> Binding<Value> {
        fieldBinding(name, fallback: fallback, componentType: componentType, completion: nil)
    }
    @MainActor package func fieldBinding(_ name: OpenUIString, fallback: Value = .null, componentType: String = "input",
                                        completion: ((Value?) -> Void)?) -> Binding<Value> {
        let binding = state.fieldBinding(form: exactFormName, name: name, fallback: fallback, componentType: componentType,
                                         expectedSourceRevision: sourceRevision, source: element, completion: completion)
        return Binding(get: { fieldValue(name, fallback: fallback) },
            set: { if canInteract { binding.wrappedValue = $0 } else { completion?(nil) } })
    }
    @MainActor @_disfavoredOverload public func initializeField<S: StringProtocol>(_ name: S, value: Value, componentType: String = "input") {
        initializeField(OpenUIString(String(name)), value:value, componentType:componentType)
    }
    @MainActor public func initializeField(_ name: OpenUIString, value: Value, componentType: String = "input") {
        guard canInteract else { return }
        state.initializeField(form: exactFormName, name: name, value: value, componentType: componentType,
                              expectedSourceRevision: sourceRevision, source: element)
    }

    @discardableResult
    @MainActor package func commitFieldAndTrigger(_ message: String, form: OpenUIString,
        name: OpenUIString, value: Value, componentType: String,
        onDispatch: (() -> Void)? = nil) async -> [ActionEvent] {
        guard canActivate, canDispatch(nil) else { return [] }
        state.setFieldValue(form: form, name: name, value: value, componentType: componentType,
                            expectedSourceRevision: sourceRevision, source: element)
        // A host state-update callback may synchronously replace this answer.
        // Preserve the captured presentation when dispatching the committed value.
        guard canActivate, canDispatch(nil) else { return [] }
        // This receipt means local event delivery only, not remote persistence.
        return await state.triggerAction(message, formName: form, action: nil, source: element,
            onDispatch: { _ in onDispatch?() })
    }

    @discardableResult
    @MainActor public func perform(_ action: ActionPlan) async -> [ActionEvent] {
        guard canInteract else { return [] }
        return await state.perform(action, formName: exactFormName, source: element)
    }

    @discardableResult
    @MainActor public func triggerAction(_ message: String, action: Value? = nil) async -> [ActionEvent] {
        guard canDispatch(action) else { return [] }
        return await state.triggerAction(message, formName: exactFormName, action: action, source: element)
    }
}
