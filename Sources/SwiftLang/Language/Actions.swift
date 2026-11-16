// SwiftLang — Action execution.
//
// Runs an `ActionPlan`'s steps in order (spec §6.3), producing host
// `ActionEvent`s. There is no upstream executor in the shipped sources (it
// lives in the framework adapters), so this follows the spec text and the
// `ActionEvent` shape in parser/types.ts.

import Foundation

/// Host-provided runtime for action execution.
public struct ActionRuntimeContext {
    /// The state store (`Set`/`Reset` write through it).
    public var store: Store
    /// Evaluate a (possibly deferred) AST to a value at step-run time.
    public var evaluate: (ASTNode) -> Value
    /// Declared `$variable` defaults, used by `Reset`.
    public var stateDefaults: [OpenUIString: Value]
    /// Fire a query by statement id (fire-and-forget; never stops the plan).
    public var runQuery: (String) -> Void
    /// Run a mutation by statement id, awaiting its outcome.
    ///
    /// Await network-backed mutations without blocking the UI executor.
    /// A failed mutation stops the remaining steps of the plan.
    public var runMutation: (String) async -> MutationOutcome
    /// Raw form state at step-run time, read lazily per step so a `@Set`
    /// earlier in the same `Action([...])` is visible to later steps.
    public var formState: () -> [(OpenUIString, Value)]
    /// The form name that triggered this action, if any.
    public var formName: OpenUIString?
    /// An async host can invalidate a plan when a stream is reset or replaced.
    public var isActive: () -> Bool
    public var onStateChange: () -> Void
    public var onEvent: ((ActionEvent) -> Void)?
    // The document lends one allowance to evaluation, each visible update and
    // this executor. Public hosts retain the same callback/step ordering.
    var nativeWorkBudget: NativeActionWorkBudget? = nil
    var onNativeLimit: (() -> Void)? = nil

    public init(
        store: Store,
        evaluate: @escaping (ASTNode) -> Value,
        stateDefaults: [OpenUIString: Value] = [:],
        runQuery: @escaping (String) -> Void,
        runMutation: @escaping (String) async -> MutationOutcome,
        formState: @escaping () -> [(OpenUIString, Value)] = { [] },
        formName: OpenUIString? = nil,
        isActive: @escaping () -> Bool = { true },
        onStateChange: @escaping () -> Void = {},
        onEvent: ((ActionEvent) -> Void)? = nil
    ) {
        self.store = store
        self.evaluate = evaluate
        self.stateDefaults = stateDefaults
        self.runQuery = runQuery
        self.runMutation = runMutation
        self.formState = formState
        self.formName = formName
        self.isActive = isActive
        self.onStateChange = onStateChange
        self.onEvent = onEvent
    }
}

/// The settled outcome of running one mutation from an action plan.
public enum MutationOutcome {
    case success(Value)
    case failure
}

/// Run an action plan's steps in order (spec §6.3), returning the host events.
/// - `set` → evaluate `valueAST` NOW, `store.set` (not pristine).
/// - `reset` → restore declared defaults from `stateDefaults` (null if none).
/// - `run` → `runQuery`/`runMutation` by statement id. A failed mutation
///   STOPS the remaining steps; a query never stops the plan.
/// - `continueConversation` → `continue_conversation` event with the message,
///   an optional `context` param, and formState/formName as of this run.
/// - `openUrl` → `open_url` event.
/// - `custom` → event typed by the action name with args keyed by name.
@MainActor
public func runActionPlan(_ plan: ActionPlan, context: ActionRuntimeContext) async -> [ActionEvent] {
    var events: [ActionEvent] = []
    let budget = context.nativeWorkBudget ?? NativeActionWorkBudget()
    var reportedLimit = false
    func fail() {
        budget.fail()
        guard !reportedLimit else { return }
        reportedLimit = true
        context.onNativeLimit?()
    }
    func active() -> Bool {
        if budget.exceeded { fail(); return false }
        return !Task.isCancelled && context.isActive()
    }
    func accept(_ cost: NativeValueCost) -> Bool {
        guard budget.consume(cost) else { fail(); return false }
        return active()
    }
    func accept(_ value: Value) -> Bool { accept(nativeValueCost(value)) }
    func emit(_ event: ActionEvent) -> Bool {
        guard accept(nativeActionEventCost(event)) else { return false }
        events.append(event)
        context.onEvent?(event)
        return active()
    }
    guard active(), accept(nativeValueCost(.actionPlan(plan))) else { return events }
    var stepsSinceYield = 0
    var workAtYield = budget.consumedWork
    for step in plan.steps {
        guard active(), budget.consume(1) else {
            if budget.exceeded { fail() }
            return events
        }
        switch step {
        case .set(let target, let valueAST):
            let value = context.evaluate(valueAST)
            guard active(), accept(value) else { return events }
            context.store.set(target, value: value, pristine: false)
            guard !context.store.nativeLimitExceeded else { fail(); return events }
            context.onStateChange()

        case .reset(let targets):
            for target in targets {
                let value = context.stateDefaults[OpenUIString(target)] ?? .null
                guard active(), accept(value) else { return events }
                context.store.set(target, value: value, pristine: true)
                guard !context.store.nativeLimitExceeded else { fail(); return events }
            }
            context.onStateChange()

        case .run(let statementId, let refType):
            switch refType {
            case .query:
                context.runQuery(statementId)
            case .mutation:
                let outcome = await context.runMutation(statementId)
                guard active() else { return events }
                switch outcome {
                case .success(let value): guard accept(value) else { return events }
                case .failure: return events // failed mutation stops remaining steps
                }
            }

        case .continueConversation(let messageAST, let contextAST):
            var params: [(OpenUIString, Value)] = []
            if let contextAST = contextAST {
                let value = context.evaluate(contextAST)
                guard active(), accept(value) else { return events }
                if !value.isNullish { params.append(("context", value)) }
            }
            let message = context.evaluate(messageAST)
            guard active(), accept(message) else { return events }
            guard emit(ActionEvent(
                type: "continue_conversation",
                params: params,
                humanFriendlyMessage: concatString(message),
                formState: context.formState(),
                formName: context.formName)) else { return events }

        case .openUrl(let urlAST):
            let url = context.evaluate(urlAST)
            guard active(), accept(url) else { return events }
            guard emit(ActionEvent(
                type: "open_url",
                params: [("url", url)],
                humanFriendlyMessage: "",
                formState: context.formState(),
                formName: context.formName)) else { return events }

        case .custom(let name, let args):
            var params: [(OpenUIString, Value)] = []
            for (key, expression) in args {
                let value = context.evaluate(expression)
                guard active(), accept(value) else { return events }
                params.append((OpenUIString(key), value))
            }
            guard emit(ActionEvent(
                type: OpenUIString(name),
                params: params,
                humanFriendlyMessage: "",
                formState: context.formState(),
                formName: context.formName)) else { return events }
        }
        guard active() else { return events }
        stepsSinceYield += 1
        if stepsSinceYield >= 32 || budget.consumedWork - workAtYield >= 4_096 {
            // A completed step is the legal suspension boundary: its Store
            // writes, publication, query reads and host callbacks already ran.
            // Never merge or move an observation across this yield.
            await Task.yield()
            guard active() else { return events }
            stepsSinceYield = 0
            workAtYield = budget.consumedWork
        }
    }
    return events
}
