import Foundation
import JavaScriptCore

/// Thin native facade over lang-core's evaluator; no DSL dispatch lives here.
public final class Evaluator {
    public let context: EvaluationContext
    public let schema: LibrarySchema
    public private(set) var errors: [OpenUIError] = []
    /// A resource failure is distinct from a recoverable expression error.
    /// Callers must not execute actions or tools using its null fallback.
    public private(set) var nativeLimitExceeded = false
    var onNativeLimit: (@Sendable () -> Void)?
    var onReferenceRead: ((String, Value) -> Void)?
    private let core = SharedCore.shared
    public init(context: EvaluationContext, schema: LibrarySchema) {
        self.context = context; self.schema = schema
    }
    // Also used by QueryManager's statement evaluation; the manager retains
    // this evaluator while upstream may read its live context asynchronously.
    func jsContext() -> JSValue {
        let ctx = context, runtime = core
        let getState: @convention(block) (String) -> JSValue = { name in runtime.encode(ctx.getState(name)) }
        let resolveRef: @convention(block) (String) -> JSValue = { [weak self] name in
            let value = ctx.resolveRef(name)
            self?.onReferenceRead?(name, value)
            return runtime.encode(value)
        }
        let report: @convention(block) (String) -> Void = { [weak self] message in
            self?.errors.append(OpenUIError(source: .runtime, code: .runtimeError, message: message));ctx.reportError?(message)
        }
        let reportLimit: @convention(block) () -> Void = { [weak self] in
            self?.recordNativeLimit()
        }
        let js = core.object()
        js.setObject(getState, forKeyedSubscript: "getState" as NSString)
        js.setObject(resolveRef, forKeyedSubscript: "resolveRef" as NSString)
        js.setObject(report, forKeyedSubscript: "reportError" as NSString)
        js.setObject(reportLimit, forKeyedSubscript: "reportNativeLimit" as NSString)
        if let scope = ctx.extraScope { js.setValue(core.object(scope.map { (OpenUIString($0.key), core.encode($0.value)) }), forProperty: "extraScope") }
        js.setValue(core.object(ctx.actions.map { name, def in
            (OpenUIString(name), core.object([("params", core.json(core.parameters(def.params)))]))
        }), forProperty: "actions")
        js.setValue(core.object(ctx.functions.map { name, function in
            let def = core.object([("params", core.json(core.parameters(function.params)))])
            if let returns = function.returns { def.setValue(core.json(returns), forProperty: "returns") }
            let fn: @convention(block) (JSValue) -> JSValue = { args in
                do { return runtime.encode(try function.fn(Dictionary(runtime.entries(args).map { ($0.0.displayString, runtime.decode($0.1)) }, uniquingKeysWith: { _, new in new }))) }
                catch { runtime.context.exception = runtime.call("error", [String(describing: error)]); return JSValue(nullIn: runtime.context) }
            }
            def.setObject(fn, forKeyedSubscript: "fn" as NSString)
            return (OpenUIString(name), def)
        }), forProperty: "functions")
        return js
    }
    func recordNativeLimit() {
        guard !nativeLimitExceeded else { return }
        nativeLimitExceeded = true
        errors.append(runtimeBudgetError())
        onNativeLimit?()
    }
    public func evaluate(_ node: ASTNode) -> Value { core.sync {
        guard !nativeLimitExceeded else { return .null }
        let outcome = core.call("boundedEvaluate", [core.ast(node), jsContext(), core.library(schema)])
        if outcome.forProperty("limitExceeded").toBool() { recordNativeLimit(); return .null }
        // The budget still checks opaque captures, while this direct native
        // path preserves the exact enum case and metadata supplied by its host.
        if case .runtimeValue(let value) = node { return value }
        return core.decode(outcome.forProperty("value"))
    } }
    public func evaluateRoot(_ result: ParseResult) -> EvaluatedElement? { core.sync {
        guard !nativeLimitExceeded, !result.nativeLimitExceeded else {
            recordNativeLimit(); return nil
        }
        let diagnostics = core.array([])
        let js: JSValue
        if let snapshot = result.coreSnapshot, snapshot.matches(result) {
            js = snapshot.value
        } else {
            js = core.object()
            js.setValue(result.root.map { core.materialized(.element($0)) } ?? JSValue(nullIn: core.context)!, forProperty: "root")
            if let expression = result.rootExpression { js.setValue(core.ast(expression), forProperty: "rootExpression") }
        }
        let contextValue = jsContext(), libraryValue = core.library(schema)
        let outcome = core.call("boundedRoot", [js, contextValue, libraryValue, JSValue(nullIn: core.context)!, diagnostics])
        errors += core.items(diagnostics).map(core.error)
        if outcome.forProperty("limitExceeded").toBool() { recordNativeLimit(); return nil }
        if case .element(let node) = core.decode(outcome.forProperty("value")) { return node };return nil
    } }
}
