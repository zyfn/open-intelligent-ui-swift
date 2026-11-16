// SwiftLang — native async transport and lifecycle bridge to lang-core.
import Foundation

public protocol ToolProvider {
    func callTool(name: OpenUIString, arguments: OpenUIObject) async throws -> Value
}

public struct ToolNotFoundError: Error, Sendable {
    public var toolName: OpenUIString
    public var availableTools: [OpenUIString]
    public init(toolName: OpenUIString, availableTools: [OpenUIString] = []) {
        self.toolName = toolName
        self.availableTools = availableTools
    }
    @_disfavoredOverload public init(toolName: String, availableTools: [String] = []) {
        self.init(toolName: OpenUIString(toolName), availableTools: availableTools.map { OpenUIString($0) })
    }

}

public enum QueryStatus: String, Sendable { case idle, loading, success, error }

public struct QueryState: Sendable {
    public var status: QueryStatus
    public var data: Value?
    public var error: OpenUIError?
    public init(status: QueryStatus, data: Value? = nil, error: OpenUIError? = nil) {
        self.status = status; self.data = data; self.error = error
    }
}

public struct MutationState: Sendable {
    public let status: QueryStatus
    public let data: Value?
    public let error: OpenUIError?
    /// The reference result object is stable until the lifecycle changes.
    public let value: Value
    public init(status: QueryStatus, data: Value? = nil, error: OpenUIError? = nil, errorText: OpenUIString? = nil) {
        self.init(status: status, data: data, error: error, errorText: errorText, sharedValue: nil)
    }
    init(status: QueryStatus, data: Value?, error: OpenUIError?, errorText: OpenUIString?, sharedValue: Value?) {
        self.status = status; self.data = data; self.error = error
        var fields = [ObjectField(key: "status", value: .string(status.rawValue))]
        if let data { fields.append(ObjectField(key: "data", value: data)) }
        if let text = errorText ?? error.map({ OpenUIString($0.message) }) { fields.append(ObjectField(key: "error", value: .string(text))) }
        self.value = sharedValue ?? .object(fields)
    }
}


import JavaScriptCore

/// Native lifecycle/transport adapter; cache, query state and mutation state are
/// executed by lang-core. Each declaration owns its upstream mutation manager so
/// replacing one declaration invalidates exactly that declaration's awaits.
public final class QueryManager {
    public typealias ToolFn = @Sendable (OpenUIObject) async throws -> Value
    private let core = SharedCore.shared
    private let provider: ToolProvider?
    private let tools: [OpenUIString: ToolFn]?
    private var manager: JSValue!
    private struct MutationManager {
        let value: JSValue
        let owner: UUID
    }
    private struct PendingTool {
        var task: Task<Void, Never>?
        let tool: OpenUIString
        let arguments: OpenUIObject
        let resolve: JSValue
        let reject: JSValue
        let canDispatch: JSValue?
        let owner: UUID
    }
    private let queryOwner = UUID()
    private var activeOwners: Set<UUID> = []
    private var mutations: [String: MutationManager] = [:]
    private var mutationTools: [String: OpenUIString] = [:]
    private var statements: [QueryStatementInfo] = []
    private var statementIDs: Set<String> = []
    private var statementEvaluator: Evaluator?
    private var listeners: [UUID: @Sendable () -> Void] = [:]
    private var pending: [UUID: PendingTool] = [:]
    private var dispatchDepth = 0
    private var dispatchAccepted = true
    private var automaticDispatchCheck: (@Sendable (Bool) async -> Bool)?
    private var nativeLimitHandler: (@Sendable () -> Void)?
    private var exceededNativeLimit = false
    private var settled: [String: [@Sendable () -> Void]] = [:]
    private var disposed = false
    var isDisposed: Bool { core.sync { disposed } }
    var nativeLimitExceeded: Bool { core.sync { exceededNativeLimit } }
    public init(provider: ToolProvider?) { self.provider = provider; tools = nil; initialize() }
    public init(tools: [String: ToolFn]) {
        provider = nil; self.tools = Dictionary(tools.map { (OpenUIString($0.key), $0.value) }, uniquingKeysWith: { _, new in new }); initialize()
    }
    public init(toolEntries: [(OpenUIString, ToolFn)]) { provider = nil; tools = Dictionary(toolEntries, uniquingKeysWith: { _, new in new }); initialize() }
    deinit { dispose() }
    private func initialize() { core.sync { manager = makeManager(owner: queryOwner) } }
    private func makeManager(owner: UUID) -> JSValue {
        activeOwners.insert(owner)
        let call: @convention(block) (JSValue, JSValue, JSValue) -> JSValue = { [weak self] name, args, canDispatch in
            guard let self else { return JSValue(undefinedIn: SharedCore.shared.context) }
            let start: @convention(block) (JSValue, JSValue) -> Void = { [weak self] resolve, reject in
                self?.startTool(name, args, resolve, reject, canDispatch: canDispatch, owner: owner)
            }
            return self.core.call("promise", [start])
        }
        let providerObject = core.object()
        providerObject.setObject(call, forKeyedSubscript: "callTool" as NSString)
        let js = core.call("queryManager", [provider != nil || tools != nil ? providerObject : JSValue(nullIn: core.context)!])
        let changed: @convention(block) () -> Void = { [weak self] in self?.notify() }
        _ = js.invokeMethod("subscribe", withArguments: [changed]);return js
    }
    private func startTool(_ name: JSValue, _ args: JSValue, _ resolve: JSValue, _ reject: JSValue,
                           canDispatch: JSValue, owner: UUID) {
        guard !disposed, activeOwners.contains(owner) else {
            reject.call(withArguments: [core.call("error", ["Disposed"])]); return
        }
        let tool = core.string(name), id = UUID()
        let decoded = core.decode(args, interpret: false)
        let arguments: OpenUIObject
        if case .object(let fields) = decoded { arguments = fields } else { arguments = OpenUIObject([]) }
        pending[id] = PendingTool(task: nil, tool: tool, arguments: arguments,
            resolve: resolve, reject: reject,
            canDispatch: canDispatch.isUndefined || canDispatch.isNull ? nil : canDispatch, owner: owner)
        if dispatchDepth == 0 { launchTool(id) }
    }
    /// All Query providers wait until the synchronous presentation commits.
    /// Automatic readers also revalidate a root changed by an async result;
    /// already checked deferred batches need only the document liveness gate.
    func setAutomaticDispatchCheck(_ check: @escaping @Sendable (Bool) async -> Bool) { core.sync {
        automaticDispatchCheck = check
    } }
    func setNativeLimitHandler(_ handler: @escaping @Sendable () -> Void) { core.sync {
        nativeLimitHandler = handler
    } }
    private func retireForNativeLimit() {
        guard !disposed else { return }
        exceededNativeLimit = true
        let notifyLimit = nativeLimitHandler
        let completionCallbacks = settled.values.flatMap { $0 }
        // Retire upstream readers before rejecting their Promises. A rejection
        // must not schedule more tools from the oversized result's defaults.
        dispose()
        notifyLimit?()
        completionCallbacks.forEach { $0() }
    }
    private func mayEnterProvider(_ id: UUID) -> Bool { core.sync {
        guard !disposed, let request = pending[id], activeOwners.contains(request.owner) else { return false }
        if let check = request.canDispatch { return check.call(withArguments: [])?.toBool() == true }
        return true
    } }
    private func launchTool(_ id: UUID, revalidateRoot: Bool = true) {
        guard !disposed, let request = pending[id], request.task == nil, activeOwners.contains(request.owner) else { return }
        let tool = request.tool, arguments = request.arguments
        let provider = self.provider, tools = self.tools, realm = core
        let preflight = request.owner == queryOwner ? automaticDispatchCheck : nil
        let task = Task { [weak self] in
            let result: Result<Value, Error>
            do {
                try Task.checkCancellation()
                if let preflight {
                    guard await preflight(revalidateRoot) else { throw CancellationError() }
                }
                // Look up the private JS check only after suspension. The task
                // must not retain it across retirement of the pending request.
                guard self?.mayEnterProvider(id) == true else { throw CancellationError() }
                try Task.checkCancellation()
                if let tools {
                    guard let fn = tools[tool] else { throw ToolNotFoundError(toolName: tool, availableTools: tools.keys.sorted { $0.codeUnits.lexicographicallyPrecedes($1.codeUnits) }) }
                    result = .success(try await fn(arguments))
                } else if let provider { result = .success(try await provider.callTool(name: tool, arguments: arguments)) }
                else { throw ToolNotFoundError(toolName: tool) }
            } catch { result = .failure(error) }
            // Keep both the manager and JS callbacks out of this suspended
            // task. Retiring pending owns their release even if the provider
            // never returns or ignores cancellation.
            realm.sync { [weak self] in self?.finishTool(id, result) }
        }
        pending[id]?.task = task
    }
    /// Let the official manager update dependencies and defaults synchronously,
    /// but enter native providers only after the host accepts the resulting UI.
    /// A failed scope retires this document and settles all its pending awaits.
    func withDeferredToolDispatch(_ operation: () -> Bool) -> Bool { core.sync {
        guard !disposed else { return false }
        if dispatchDepth == 0 { dispatchAccepted = true }
        dispatchDepth += 1
        let accepted = operation()
        dispatchAccepted = dispatchAccepted && accepted && !disposed
        dispatchDepth -= 1
        if dispatchDepth == 0 {
            if dispatchAccepted {
                let deferred = pending.compactMap { id, request in request.task == nil ? id : nil }
                deferred.forEach { launchTool($0, revalidateRoot: false) }
            } else {
                dispose()
            }
        }
        return dispatchAccepted && !disposed
    } }
    private func finishTool(_ id: UUID, _ result: Result<Value, Error>) { core.sync {
        guard let request = pending.removeValue(forKey: id), !disposed else { return }
        switch result {
        case .success(let value):
            guard !nativeValueExceedsLimits(value) else {
                retireForNativeLimit()
                request.reject.call(withArguments: [core.call("error", [runtimeBudgetError().message])])
                return
            }
            request.resolve.call(withArguments: [core.encode(value)])
        case .failure(let error):
            let js: JSValue
            if let error = error as? ToolNotFoundError { js = core.call("toolError", [core.string(error.toolName), core.array(error.availableTools.map(core.string))]) }
            else if let error = error as? MCPToolError { js = core.call("mcpError", [core.string(error.toolErrorText)]) }
            else { js = core.call("error", [String(describing: error)]) }
            request.reject.call(withArguments: [js])
        }
    } }
    @discardableResult public func subscribe(_ listener: @escaping @Sendable () -> Void) -> () -> Void {
        let id = UUID();core.sync { if !disposed { listeners[id] = listener } }
        return { [weak self] in self?.core.sync { _ = self?.listeners.removeValue(forKey: id) } }
    }
    private func notify() {
        for (id, callbacks) in settled where manager?.invokeMethod("isLoading", withArguments: [id]).toBool() == false {
            settled.removeValue(forKey: id);callbacks.forEach { $0() }
        }
        Array(listeners.values).forEach { $0() }
    }
    /// Execute parsed declarations through the official dependency-aware
    /// manager. The evaluator's state and reference callbacks must read live
    /// values; capture this manager weakly in those callbacks.
    public func evaluateStatements(_ statements: [QueryStatementInfo], evaluator: Evaluator) { core.sync {
        guard !disposed else { return }
        self.statements = statements
        statementIDs = Set(statements.filter(\.complete).map(\.statementId))
        statementEvaluator = evaluator
        evaluateStatementQueries()
    } }
    private func evaluateStatementQueries() {
        guard !disposed, let evaluator = statementEvaluator else { return }
        guard !evaluator.nativeLimitExceeded else { retireForNativeLimit(); return }
        let nodes = statements.map { statement -> JSValue in
            let node = core.object([
                ("statementId", core.string(OpenUIString(statement.statementId))),
                ("toolAST", statement.toolAST.map(core.ast) ?? JSValue(nullIn: core.context)!),
                ("argsAST", statement.argsAST.map(core.ast) ?? JSValue(nullIn: core.context)!),
                ("defaultsAST", statement.defaultsAST.map(core.ast) ?? JSValue(nullIn: core.context)!),
                ("refreshAST", statement.refreshAST.map(core.ast) ?? JSValue(nullIn: core.context)!),
                ("complete", JSValue(bool: statement.complete, in: core.context)!)
            ])
            if let deps = statement.deps { node.setValue(deps, forProperty: "deps") }
            if let waitFor = statement.waitFor { node.setValue(waitFor, forProperty: "waitFor") }
            return node
        }
        let context = evaluator.jsContext()
        guard !evaluator.nativeLimitExceeded else { retireForNativeLimit(); return }
        _ = core.call("evaluateQueryStatements", [manager!, core.array(nodes), context])
        if evaluator.nativeLimitExceeded { retireForNativeLimit() }
    }
    public func invalidateQuery(statementId: String) { core.sync {
        guard !disposed, statementEvaluator?.nativeLimitExceeded != true, statementIDs.contains(statementId) else { return }
        _ = manager.invokeMethod("invalidate", withArguments: [[statementId]])
    } }
    public func runQuery(statementId: String, tool: OpenUIString, args: Value, defaults: Value, onSettled: (@Sendable () -> Void)? = nil) { core.sync {
        guard !disposed else { return }
        guard let evaluator = statementEvaluator else { return }
        if let onSettled { settled[statementId, default: []].append(onSettled) }
        guard !evaluator.nativeLimitExceeded else { retireForNativeLimit(); return }
        guard !nativeValueExceedsLimits(args), !nativeValueExceedsLimits(defaults) else {
            retireForNativeLimit(); return
        }
        if let index = statements.firstIndex(where: { $0.statementId == statementId }) {
            let previous = statements[index]
            let sameRequest = previous.toolAST.map(evaluator.evaluate) == .string(tool)
                && previous.argsAST.map(evaluator.evaluate) == args
            guard !disposed else { return }
            guard !evaluator.nativeLimitExceeded else { retireForNativeLimit(); return }
            if sameRequest {
                // An explicit retry must not replace a parsed query with its
                // current values: doing so would lose future dependency reads.
                let previousDefaults = previous.defaultsAST.map(evaluator.evaluate) ?? .null
                guard !disposed else { return }
                guard !evaluator.nativeLimitExceeded else { retireForNativeLimit(); return }
                if previousDefaults != defaults {
                    statements[index].defaultsAST = .runtimeValue(defaults)
                    evaluateStatementQueries()
                }
                invalidateQuery(statementId: statementId)
                return
            }
            statements[index].toolAST = .str(tool)
            statements[index].argsAST = .runtimeValue(args)
            statements[index].defaultsAST = .runtimeValue(defaults)
            statements[index].waitFor = nil
            statements[index].complete = true
        } else {
            // Adding an ad hoc request must not switch the official manager
            // out of statement mode and discard the active dependency graph.
            statements.append(QueryStatementInfo(statementId: statementId, toolAST: .str(tool),
                argsAST: .runtimeValue(args), defaultsAST: .runtimeValue(defaults),
                refreshAST: nil, deps: nil, complete: true))
        }
        statementIDs.insert(statementId)
        evaluateStatementQueries()
        guard !disposed else { return }
        if manager.invokeMethod("isLoading", withArguments: [statementId]).toBool() == false {
            invalidateQuery(statementId: statementId)
        }
        return
    } }
    public func queryState(for id: String) -> QueryState? { core.sync {
        guard statementIDs.contains(id) else { return nil }
        let snapshot = manager.invokeMethod("getSnapshot", withArguments: [])!
        let error = core.items(snapshot.forProperty("__openui_errors")).first { $0.forProperty("statementId").toString() == id }.map(core.error)
        let loading = manager.invokeMethod("isLoading", withArguments: [id]).toBool()
        return QueryState(status: loading ? .loading : error != nil ? .error : provider == nil && tools == nil ? .idle : .success, data: core.decode(manager.invokeMethod("getResult", withArguments: [id])), error: error)
    } }
    public func registerMutations(_ declarations: [String: OpenUIString]) { core.sync {
        guard !disposed else { return }
        retireMutations(mutations.keys.filter { declarations[$0] != mutationTools[$0] })
        mutationTools = declarations
        for (id, name) in declarations where mutations[id] == nil {
            let owner = UUID(), js = makeManager(owner: owner)
            _ = js.invokeMethod("registerMutations", withArguments: [core.array([core.object([("statementId", core.string(OpenUIString(id))), ("toolName", core.string(name))])])])
            mutations[id] = MutationManager(value: js, owner: owner)
        }
    } }
    private func retireMutations(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let retired = ids.compactMap { mutations.removeValue(forKey: $0) }
        let owners = Set(retired.map(\.owner))
        activeOwners.subtract(owners)
        retired.forEach { _ = $0.value.invokeMethod("dispose", withArguments: []) }
        // A provider need not cooperate with Task cancellation. Reject the
        // bridge as well so an action awaiting this declaration can finish.
        // Scan pending once even when a patch retires many declarations.
        cancelPending(owners: owners)
    }
    private func cancelPending(owners: Set<UUID>? = nil) {
        let ids = pending.compactMap { id, request in (owners?.contains(request.owner) ?? true) ? id : nil }
        let requests = ids.compactMap { pending.removeValue(forKey: $0) }
        for request in requests {
            request.task?.cancel()
            request.reject.call(withArguments: [core.call("error", ["Disposed"])])
        }
    }
    public func invalidateMutations() { core.sync {
        guard !disposed else { return }
        let declarations = mutationTools
        retireMutations(Array(mutations.keys))
        registerMutations(declarations)
    } }
    public func mutationState(for id: String) -> MutationState? { core.sync {
        guard let js = mutations[id]?.value else { return nil }
        let value = js.invokeMethod("getMutationResult", withArguments: [id])!
        let snapshot = js.invokeMethod("getSnapshot", withArguments: [])!
        let error = core.items(snapshot.forProperty("__openui_errors")).first.map(core.error)
        return MutationState(status: QueryStatus(rawValue: value.forProperty("status").toString()) ?? .idle,
            data: value.forProperty("data").isUndefined ? nil : core.decode(value.forProperty("data")), error: error,
            errorText: value.forProperty("error").isUndefined || value.forProperty("error").isNull ? nil : core.string(value.forProperty("error")), sharedValue: core.decode(value))
    } }
    public func runMutation(statementId: String, tool: OpenUIString, args: Value) async -> MutationState {
        await withCheckedContinuation { continuation in core.sync {
            guard !disposed else { continuation.resume(returning: MutationState(status: .error));return }
            guard !nativeValueExceedsLimits(args) else {
                retireForNativeLimit()
                continuation.resume(returning: MutationState(status: .error, error: runtimeBudgetError()))
                return
            }
            if mutationTools[statementId] != tool {
                var declarations = mutationTools;declarations[statementId] = tool;registerMutations(declarations)
            }
            guard let js = mutations[statementId]?.value, js.invokeMethod("getMutationResult", withArguments: [statementId]).forProperty("status").toString() != "loading" else {
                continuation.resume(returning: mutationState(for: statementId) ?? MutationState(status: .error));return
            }
            let promise = js.invokeMethod("fireMutation", withArguments: [statementId, core.encode(args)])!
            let finish: @convention(block) (Bool) -> Void = { [weak self] success in
                guard let self else { continuation.resume(returning: MutationState(status: .error));return }
                self.core.sync {
                    guard self.mutations[statementId]?.value === js else { continuation.resume(returning: MutationState(status: .error));return }
                    continuation.resume(returning: self.mutationState(for: statementId) ?? MutationState(status: .error))
                }
            }
            _ = promise.invokeMethod("then", withArguments: [finish])
        } }
    }
    public func dispose() { core.sync {
        guard !disposed else { return };disposed = true
        activeOwners.removeAll()
        _ = manager?.invokeMethod("dispose", withArguments: [])
        mutations.values.forEach { _ = $0.value.invokeMethod("dispose", withArguments: []) }
        listeners.removeAll();settled.removeAll();mutations.removeAll()
        statements = []; statementIDs = []; statementEvaluator = nil
        automaticDispatchCheck = nil
        nativeLimitHandler = nil
        manager = nil
        cancelPending()
    } }
}
