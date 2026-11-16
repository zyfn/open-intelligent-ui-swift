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

    @MainActor public init(element: EvaluatedElement, registry: OpenUIComponentRegistry, state: OpenUIState,
                values: OpenUIContextValues = OpenUIContextValues(), resources: [String: Value] = [:],
                formName: String? = nil, exactFormName: OpenUIString? = nil) {
        self.element = element; self.registry = registry; self.state = state
        self.values = values; self.resources = resources; self.formName = exactFormName?.displayString ?? formName
        self.exactFormName = exactFormName ?? formName.map { OpenUIString($0) }
        self.sourceRevision = state.sourceRevision
        self.isStreaming = !state.isComplete
        self.isQueryLoading = state.isQueryLoading
        self.presentationReadiness = element.sourceReadiness
        let queries = element.sourceReadiness.queryDependencies.map { state.queryStates[$0.displayString] }
        self.hasPendingData = queries.contains { $0?.status == .loading || (!state.isComplete && ($0 == nil || $0?.status == .idle)) }
        self.hasDataFailure = queries.contains { $0?.status == .error }
        self.hasInterruptedData = state.isInterrupted && queries.contains { $0 == nil || $0?.status == .idle }
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
    /// Local presentation controls such as Modal close can update their value
    /// while streaming. Epoch checks still reject callbacks from replaced UI.
    @MainActor package func presentationBinding(_ name: String) -> Binding<Value>? {
        guard let binding = state.binding(for: element, prop: name, expectedSourceRevision: sourceRevision,
                                          presentation: true) else { return nil }
        return Binding(get: { binding.wrappedValue }, set: { if isCurrentPresentation { binding.wrappedValue = $0 } })
    }
    @MainActor package func presentationFieldValue(_ name: OpenUIString, fallback: Value) -> Value {
        state.fieldValue(form: exactFormName, name: name, fallback: fallback)
    }
    @MainActor package func setPresentationFieldValue(_ name: OpenUIString, value: Value) {
        guard isCurrentPresentation else { return }
        state.setFieldValue(form: exactFormName, name: name, value: value, componentType: nil,
                            expectedSourceRevision: sourceRevision, source: element, presentation: true)
    }
    /// Editing records can be retained by the document. Their callbacks must
    /// not retain the document in return, or releasing a renderer leaks it.
    @MainActor package func weakOperation<Input>(_ body: @escaping (OpenUIComponentContext, Input) -> Void) -> (Input) -> Void {
        let element = element, registry = registry, values = values
        let resources = resources, form = exactFormName, revision = sourceRevision
        let scopeReady = interactionScopeReady
        return { [weak state] value in
            guard let state, state.sourceRevision == revision else { return }
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
            values: values, resources: resources, exactFormName: form)
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
        guard let binding = state.binding(for: element, prop: name, expectedSourceRevision: sourceRevision) else { return nil }
        return Binding(get: { binding.wrappedValue }, set: { if canInteract { binding.wrappedValue = $0 } })
    }
    public func action(_ name: String = "action") -> ActionPlan? { PropValue.actionPlan(element, name) }

    @MainActor @_disfavoredOverload public func fieldValue<S: StringProtocol>(_ name: S, fallback: Value = .null) -> Value { fieldValue(OpenUIString(String(name)), fallback:fallback) }
    @MainActor public func fieldValue(_ name: OpenUIString, fallback: Value = .null) -> Value {
        state.fieldValue(form: exactFormName, name: name, fallback: fallback)
    }
    @MainActor @_disfavoredOverload public func fieldBinding<S: StringProtocol>(_ name: S, fallback: Value = .null, componentType: String = "input") -> Binding<Value> {
        fieldBinding(OpenUIString(String(name)), fallback:fallback, componentType:componentType)
    }
    @MainActor public func fieldBinding(_ name: OpenUIString, fallback: Value = .null, componentType: String = "input") -> Binding<Value> {
        let binding = state.fieldBinding(form: exactFormName, name: name, fallback: fallback, componentType: componentType,
                                         expectedSourceRevision: sourceRevision, source: element)
        return Binding(get: { binding.wrappedValue }, set: { if canInteract { binding.wrappedValue = $0 } })
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
