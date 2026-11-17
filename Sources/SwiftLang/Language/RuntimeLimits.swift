// Bounded recursive work: model output must not exhaust the native call stack.
import Foundation

/// Native safety budget, not a new language parameter or an upstream parser.
public enum OpenUIRuntimeBudget {
    public static let maximumSourceUTF16 = 1_048_576
    public static func acceptsSource(_ source: String) -> Bool {
        var count = 0
        for _ in source.utf16 {
            count += 1
            if count > maximumSourceUTF16 { return false }
        }
        return true
    }
}

/// Check host/provider values before the bridge allocates their JavaScript
/// projection. Pure data uses the JS output limits and counts each occurrence
/// of a shared subtree. Native-only readiness, captured values and action ASTs
/// are also charged: their encoding costs work even when hidden from the final
/// JS object. That makes this boundary deliberately conservative for non-data
/// values; it does not evaluate expressions or change the Lang contract.
func nativeValueExceedsLimits(_ value: Value) -> Bool {
    nativeValueCost(value).exceeds
}

func nativeValueCost(_ value: Value) -> NativeValueCost { NativeValueBudget().value(value, at: 0) }

/// MCP JSON is still host input before it becomes a Lang Value. Inspect the
/// original tree before allocating a duplicate JavaScript representation.
func nativeJSONExceedsLimits(_ value: JSONValue) -> Bool {
    NativeValueBudget().json(value, at: 0).exceeds
}

/// Inspect a host scope without first copying its keys into OpenUIString or
/// allocating the object projection that this check is meant to protect.
func nativeScopeExceedsLimits(_ values: [String: Value]) -> Bool {
    NativeValueBudget().scope(values).exceeds
}

func nativeStateExceedsLimits(_ values: [OpenUIString: Value]) -> Bool {
    NativeValueBudget().state(values).exceeds
}

/// Public native ASTs, including opaque runtime captures, also allocate before
/// JS evaluation starts. Measure their transport graph without a wrapper value
/// or a second parser; AST/container overhead is part of this native boundary.
func nativeASTExceedsLimits(_ node: ASTNode) -> Bool {
    nativeASTCost(node).exceeds
}

func nativeASTCost(_ node: ASTNode) -> NativeValueCost { NativeValueBudget().expression(node) }
func nativeMaterializedCost(_ value: Materialized) -> NativeValueCost {
    NativeValueBudget().materialized(value, at: 0)
}
func nativeQueryStatementsCost(_ statements: [QueryStatementInfo]) -> NativeValueCost { NativeValueBudget().queries(statements) }
func nativeMutationDeclarationsExceedLimits(_ declarations: [String: OpenUIString]) -> Bool {
    NativeValueBudget().mutationDeclarations(declarations).exceeds
}
func nativeParseProjectionCost(_ result: ParseResult) -> NativeValueCost { NativeValueBudget().projection(result) }
func nativeActionEventCost(_ event: ActionEvent) -> NativeValueCost { NativeValueBudget().event(event) }

/// Immutable graph accounting shared by Store preflight and action execution.
/// Costs count occurrences, including a shared value assigned to two fields.
struct NativeValueCost: Equatable {
    static let maximumNodes = 100_000
    static let maximumDepth = 256
    static let maximumElements = 4_096
    static let maximumUTF16 = OpenUIRuntimeBudget.maximumSourceUTF16
    static let oversized = Self(nodes: maximumNodes + 1, depth: maximumDepth + 1,
        elements: maximumElements + 1, utf16: maximumUTF16 + 1)
    static var container: Self { Self(depth: 1) }

    var nodes = 1
    var depth = 0
    var elements = 0
    var utf16 = 0
    var workUnits: Int { nodes + (utf16 + 63) / 64 }
    var exceeds: Bool {
        nodes > Self.maximumNodes || depth > Self.maximumDepth ||
        elements > Self.maximumElements || utf16 > Self.maximumUTF16
    }

    mutating func append(_ child: @autoclosure () -> Self, keyUnits: Int = 0) {
        guard !exceeds else { return }
        utf16 = min(Self.maximumUTF16 + 1, utf16 + min(Self.maximumUTF16 + 1, keyUnits))
        guard !exceeds else { return }
        let next = child()
        nodes = min(Self.maximumNodes + 1, nodes + next.nodes)
        depth = min(Self.maximumDepth + 1, max(depth, next.depth + 1))
        elements = min(Self.maximumElements + 1, elements + next.elements)
        utf16 = min(Self.maximumUTF16 + 1, utf16 + next.utf16)
    }
}

/// One action owns one allowance across all synchronous evaluation/publication
/// boundaries. The realm and MainActor can both report work; no JS value or
/// callback is retained here, and no unrelated action shares this counter.
final class NativeActionWorkBudget: @unchecked Sendable {
    static let maximumWork = 100_000
    private let lock = NSLock()
    private let limit: Int
    private var work = 0
    private var failed = false
    init(maximumWork: Int = NativeActionWorkBudget.maximumWork) { limit = max(0, maximumWork) }
    var consumedWork: Int { lock.lock(); defer { lock.unlock() }; return work }
    var remainingWork: Int { lock.lock(); defer { lock.unlock() }; return failed ? 0 : limit - work }
    var exceeded: Bool { lock.lock(); defer { lock.unlock() }; return failed }
    @discardableResult func consume(_ amount: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !failed else { return false }
        let remaining = limit - work
        guard amount >= 0, amount <= remaining else { failed = true; return false }
        work += amount
        return true
    }
    @discardableResult func consume(_ cost: NativeValueCost) -> Bool {
        guard !cost.exceeds else { fail(); return false }
        return consume(cost.workUnits)
    }
    func fail() { lock.lock(); failed = true; lock.unlock() }
}

/// Reference containers are immutable. Memoizing their relative cost avoids
/// expanding a DAG, while adding that cost on every edge retains output limits.
/// The cache is local to this check and never retains a provider's value graph.
private final class NativeValueBudget {
    typealias Cost = NativeValueCost
    private var memo: [ObjectIdentifier: Cost] = [:]
    private var path: Set<ObjectIdentifier> = []
    private var inspectedNodes = 0
    private var inspectedUTF16 = 0
    private var exhausted = false

    // Child costs alone are insufficient to bound the check: a deep spine can
    // place a large valid sibling before every next level. Share one inspection
    // allowance so even a rejected graph stops before walking all those siblings.
    // Every visited input node contributes at least one projected node, so an
    // otherwise valid graph cannot exhaust this allowance.
    private func visit() -> Bool {
        guard !exhausted else { return false }
        inspectedNodes += 1
        exhausted = inspectedNodes > Cost.maximumNodes
        return !exhausted
    }

    private func units(_ text: String) -> Int {
        guard !exhausted else { return Cost.maximumUTF16 + 1 }
        var count = 0
        for _ in text.utf16 {
            count += 1
            inspectedUTF16 += 1
            if inspectedUTF16 > Cost.maximumUTF16 {
                exhausted = true
                return Cost.maximumUTF16 + 1
            }
        }
        return count
    }
    private func text(_ text: String) -> Cost { Cost(utf16: units(text)) }
    private func text(_ text: OpenUIString) -> Cost {
        Cost(utf16: min(Cost.maximumUTF16 + 1, text.count))
    }
    private func leaf(_ cost: @autoclosure () -> Cost) -> Cost {
        guard visit() else { return .oversized }
        return cost()
    }
    private func reference(_ object: AnyObject, at depth: Int, _ measure: () -> Cost) -> Cost {
        guard depth < Cost.maximumDepth else { return .oversized }
        let id = ObjectIdentifier(object)
        guard !path.contains(id) else { return .oversized }
        if let cost = memo[id] {
            return depth + cost.depth > Cost.maximumDepth ? .oversized : cost
        }
        path.insert(id)
        defer { path.remove(id) }
        let cost = measure()
        memo[id] = cost
        return cost
    }
    private func sequence<C: Collection>(_ items: C, at depth: Int,
        _ measure: (C.Element, Int) -> Cost) -> Cost {
        guard depth < Cost.maximumDepth, items.count < Cost.maximumNodes else { return .oversized }
        var cost = Cost.container
        for item in items {
            cost.append(measure(item, depth + 1))
            if cost.exceeds { break }
        }
        return cost
    }
    private func fields<C: Collection>(_ items: C, at depth: Int,
        key: (C.Element) -> Int, _ measure: (C.Element, Int) -> Cost) -> Cost {
        guard depth < Cost.maximumDepth, items.count < Cost.maximumNodes else { return .oversized }
        var cost = Cost.container
        for item in items {
            cost.append(measure(item, depth + 1), keyUnits: key(item))
            if cost.exceeds { break }
        }
        return cost
    }
    func scope(_ values: [String: Value]) -> Cost {
        guard visit() else { return .oversized }
        return fields(values, at: 0, key: { self.units($0.key) }) {
            self.value($0.value, at: $1)
        }
    }
    func state(_ values: [OpenUIString: Value]) -> Cost {
        guard visit() else { return .oversized }
        return fields(values, at: 0, key: { $0.key.count }) {
            self.value($0.value, at: $1)
        }
    }
    func json(_ value: JSONValue, at depth: Int) -> Cost {
        guard visit(), depth <= Cost.maximumDepth else { return .oversized }
        switch value {
        case .null, .boolean, .number: return Cost()
        case .string(let value): return text(value)
        case .array(let values):
            return sequence(values, at: depth) { self.json($0, at: $1) }
        case .object(let values):
            var hasElementMarker = false
            var cost = fields(values, at: depth, key: { $0.key.count }) { field, level in
                if field.key == "type", case .string(let type) = field.value, type == "element" {
                    hasElementMarker = true
                }
                return self.json(field.value, at: level)
            }
            if hasElementMarker { cost.elements = min(Cost.maximumElements + 1, cost.elements + 1) }
            return cost
        }
    }
    func expression(_ node: ASTNode) -> Cost { ast(node, at: 0) }
    func queries(_ statements: [QueryStatementInfo]) -> Cost {
        guard visit() else { return .oversized }
        return sequence(statements, at: 0) { statement, depth in
            var cost = Cost.container
            cost.append(self.text(statement.statementId), keyUnits: 11)
            for (key, node) in [("toolAST", statement.toolAST), ("argsAST", statement.argsAST),
                                ("defaultsAST", statement.defaultsAST), ("refreshAST", statement.refreshAST)] {
                cost.append(node.map { self.ast($0, at: depth + 1) } ?? Cost(), keyUnits: key.utf16.count)
                if cost.exceeds { return cost }
            }
            cost.append(Cost(), keyUnits: 8) // complete
            for (key, names) in [("deps", statement.deps), ("waitFor", statement.waitFor)] {
                guard let names else { continue }
                cost.append(self.sequence(names, at: depth + 1) { name, _ in self.leaf(self.text(name)) },
                            keyUnits: key.utf16.count)
                if cost.exceeds { return cost }
            }
            return cost
        }
    }
    func mutationDeclarations(_ declarations: [String: OpenUIString]) -> Cost {
        guard visit() else { return .oversized }
        return sequence(declarations, at: 0) { field, _ in
            guard self.visit() else { return .oversized }
            var cost = Cost.container
            cost.append(self.text(field.key), keyUnits: 11)
            cost.append(self.text(field.value), keyUnits: 8)
            return cost
        }
    }
    func projection(_ result: ParseResult) -> Cost {
        guard visit() else { return .oversized }
        var cost = Cost.container
        if let root = result.root { cost.append(materialized(.element(root), at: 1), keyUnits: 4) }
        if let expression = result.rootExpression { cost.append(ast(expression, at: 1), keyUnits: 14) }
        return cost
    }
    func event(_ event: ActionEvent) -> Cost {
        guard visit() else { return .oversized }
        var cost = Cost.container
        cost.append(text(event.type), keyUnits: 4)
        cost.append(fields(event.params, at: 1, key: { $0.0.count }) { self.value($0.1, at: $1) }, keyUnits: 6)
        cost.append(text(event.humanFriendlyMessage), keyUnits: 20)
        if let state = event.formState {
            cost.append(fields(state, at: 1, key: { $0.0.count }) { self.value($0.1, at: $1) }, keyUnits: 9)
        }
        if let name = event.formName { cost.append(text(name), keyUnits: 8) }
        return cost
    }
    func materialized(_ value: Materialized, at depth: Int) -> Cost {
        switch value {
        case .stateDefault(let value): return self.value(value.value, at: depth)
        case .value(let value): return self.value(value, at: depth)
        case .null: return leaf(Cost())
        case .expr(let node): return ast(node, at: depth)
        case .array(let values):
            guard visit() else { return .oversized }
            return sequence(values, at: depth) { self.materialized($0, at: $1) }
        case .object(let entries):
            guard visit() else { return .oversized }
            return fields(entries, at: depth, key: { $0.0.count }) { self.materialized($0.1, at: $1) }
        case .element(let element):
            guard visit(), depth < Cost.maximumDepth else { return .oversized }
            var cost = Cost(depth: 1, elements: 1)
            cost.append(text("element" as String), keyUnits: 4)
            cost.append(text(element.typeName), keyUnits: 8)
            cost.append(fields(element.props, at: depth + 1, key: { self.units($0.key) }) {
                self.materialized($0.value, at: $1)
            }, keyUnits: 5)
            cost.append(Cost(), keyUnits: 7)
            cost.append(Cost(), keyUnits: 15)
            if let id = element.statementId { cost.append(text(id), keyUnits: 11) }
            return cost
        }
    }
    func value(_ value: Value, at depth: Int) -> Cost {
        guard visit() else { return .oversized }
        switch value {
        case .string(let string): return text(string)
        case .number, .boolean, .null, .undefined: return Cost()
        case .array, .object:
            return data(value, at: depth)
        case .element(let element):
            return reference(element, at: depth) { self.element(element, at: depth) }
        case .actionPlan(let plan):
            return reference(plan, at: depth) {
                var cost = Cost.container
                cost.append(sequence(plan.steps, at: depth + 1) { self.step($0, at: $1) }, keyUnits: 5)
                return cost
            }
        case .binding(let binding), .reactiveBinding(let binding):
            return reference(binding, at: depth) {
                var cost = Cost.container
                cost.append(text("assign" as String), keyUnits: 10)
                cost.append(text(binding.target), keyUnits: 6)
                cost.append(ast(binding.expression, at: depth + 1), keyUnits: 4)
                return cost
            }
        }
    }

    /// A provider completes on a concurrency worker, whose stack is smaller
    /// than the main thread's. Even the depth check must not recurse through
    /// hundreds of generic collection/closure frames before it can reject a
    /// data graph. Keep one frame per open container and visit one child at a
    /// time; wide inputs never allocate a second work list of all their values.
    private struct DataFrame {
        let value: Value
        let identity: ObjectIdentifier
        let depth: Int
        var index = 0
        var cost = Cost.container
        var hasElementMarker = false

        mutating func next() -> Value? {
            guard !cost.exceeds else { return nil }
            switch value {
            case .array(let array):
                guard index < array.count else { return nil }
                defer { index += 1 }
                return array[index]
            case .object(let object):
                guard index < object.count else { return nil }
                let field = object[index]
                index += 1
                cost.utf16 = min(Cost.maximumUTF16 + 1,
                    cost.utf16 + min(Cost.maximumUTF16 + 1, field.key.count))
                guard !cost.exceeds else { return nil }
                if field.key == "type", case .string(let type) = field.value, type == "element" {
                    hasElementMarker = true
                }
                return field.value
            default:
                return nil
            }
        }

        var completedCost: Cost {
            var result = cost
            // Match the JS output guard without interpreting plain data as a
            // native component. Each occurrence of a shared marker is charged.
            if hasElementMarker { result.elements = min(Cost.maximumElements + 1, result.elements + 1) }
            return result
        }
    }

    private func data(_ root: Value, at rootDepth: Int) -> Cost {
        var frames: [DataFrame] = []
        var next: (value: Value, depth: Int)? = (root, rootDepth)
        var first = true // value(_:at:) has already charged the root visit.
        var measured = Cost()
        while true {
            if let input = next {
                next = nil
                let object: AnyObject?
                let count: Int
                switch input.value {
                case .array(let array): object = array; count = array.count
                case .object(let fields): object = fields; count = fields.count
                default: object = nil; count = 0
                }
                if let object {
                    let visited = first || visit()
                    first = false
                    let id = ObjectIdentifier(object)
                    if !visited || input.depth >= Cost.maximumDepth || path.contains(id) {
                        measured = .oversized
                    } else if let cached = memo[id] {
                        measured = input.depth + cached.depth > Cost.maximumDepth ? .oversized : cached
                    } else if count >= Cost.maximumNodes {
                        measured = .oversized
                    } else {
                        path.insert(id)
                        var frame = DataFrame(value: input.value, identity: id, depth: input.depth)
                        if let child = frame.next() {
                            frames.append(frame)
                            next = (child, input.depth + 1)
                            continue
                        }
                        measured = frame.completedCost
                        memo[id] = measured
                        path.remove(id)
                    }
                } else {
                    measured = value(input.value, at: input.depth)
                }
            }
            guard var parent = frames.popLast() else { return measured }
            parent.cost.append(measured)
            if let child = parent.next() {
                frames.append(parent)
                next = (child, parent.depth + 1)
            } else {
                measured = parent.completedCost
                memo[parent.identity] = measured
                path.remove(parent.identity)
            }
        }
    }
    private func element(_ element: EvaluatedElement, at depth: Int) -> Cost {
        var cost = Cost(depth: 1, elements: 1)
        cost.append(text("element" as String), keyUnits: 4)
        cost.append(text(element.typeName), keyUnits: 8)
        cost.append(fields(element.props, at: depth + 1, key: { self.units($0.0) }) {
            self.value($0.1, at: $1)
        }, keyUnits: 5)
        cost.append(Cost(), keyUnits: 7)
        if let id = element.statementId { cost.append(text(id), keyUnits: 11) }
        // tagNativeSource receives a separately encoded metadata graph. Charge
        // it as an auxiliary child before encodeReadiness can recurse/allocate.
        cost.append(readiness(element.sourceReadiness, at: depth + 1))
        return cost
    }
    private func readiness(_ value: NativeSourceReadiness, at depth: Int) -> Cost {
        guard visit(), depth < Cost.maximumDepth else { return .oversized }
        var cost = Cost.container
        cost.append(Cost(), keyUnits: 8) // complete
        cost.append(Cost(), keyUnits: 6) // closed
        cost.append(fields(value.children, at: depth + 1, key: { $0.key.count }) {
            self.readiness($0.value, at: $1)
        }, keyUnits: 8)
        cost.append(sequence(value.queryDependencies, at: depth + 1) { item, _ in self.leaf(self.text(item)) }, keyUnits: 7)
        cost.append(Cost(), keyUnits: 8) // observed
        if value.expectedCount != nil { cost.append(Cost(), keyUnits: 5) }
        if let slots = value.valueIndices {
            cost.append(sequence(slots, at: depth + 1) { _, _ in self.leaf(Cost()) }, keyUnits: 5)
        }
        if !value.pendingChildren.isEmpty {
            cost.append(fields(value.pendingChildren, at: depth + 1, key: { self.units(String($0.key)) }) {
                self.readiness($0.value, at: $1)
            }, keyUnits: 7)
        }
        if let hint = value.placeholder {
            cost.append(placeholder(hint, at: depth + 1), keyUnits: 11)
        }
        return cost
    }
    private func placeholder(_ hint: NativeComponentPlaceholder, at depth: Int) -> Cost {
        guard visit(), depth < Cost.maximumDepth else { return .oversized }
        var cost = Cost.container
        cost.append(text(hint.typeName), keyUnits: 4)
        cost.append(fields(hint.properties, at: depth + 1, key: { $0.key.count }) {
            self.value($0.value, at: $1)
        }, keyUnits: 5)
        if let id = hint.statementId { cost.append(text(id), keyUnits: 2) }
        return cost
    }
    private func step(_ step: ActionStep, at depth: Int) -> Cost {
        guard visit(), depth < Cost.maximumDepth else { return .oversized }
        var cost = Cost.container
        switch step {
        case .run(let id, let refType):
            cost.append(text("run" as String), keyUnits: 4)
            cost.append(text(id), keyUnits: 11)
            cost.append(text(refType.rawValue), keyUnits: 7)
        case .set(let target, let node):
            cost.append(text("set" as String), keyUnits: 4)
            cost.append(text(target), keyUnits: 6)
            cost.append(ast(node, at: depth + 1), keyUnits: 8)
        case .reset(let targets):
            cost.append(text("reset" as String), keyUnits: 4)
            cost.append(sequence(targets, at: depth + 1) { item, _ in self.leaf(self.text(item)) }, keyUnits: 7)
        case .continueConversation(let message, let context):
            cost.append(text("continue_conversation" as String), keyUnits: 4)
            cost.append(ast(message, at: depth + 1), keyUnits: 7)
            if let context { cost.append(ast(context, at: depth + 1), keyUnits: 7) }
            else { cost.append(Cost(), keyUnits: 7) }
        case .openUrl(let url):
            cost.append(text("open_url" as String), keyUnits: 4)
            cost.append(ast(url, at: depth + 1), keyUnits: 3)
        case .custom(let name, let args):
            cost.append(text("custom_action" as String), keyUnits: 4)
            cost.append(text(name), keyUnits: 4)
            cost.append(fields(args, at: depth + 1, key: { self.units($0.0) }) {
                self.ast($0.1, at: $1)
            }, keyUnits: 6)
        }
        // Literal action arguments are inspected as ASTs, without allocating
        // literalValue's temporary containers or evaluating nonliteral nodes.
        return cost
    }
    private func ast(_ node: ASTNode, at depth: Int) -> Cost {
        guard visit(), depth < Cost.maximumDepth else { return .oversized }
        var cost = Cost.container
        switch node {
        case .str(let string):
            cost.append(text("Str" as String), keyUnits: 1)
            cost.append(text(string), keyUnits: 1)
        case .num:
            cost.append(text("Num" as String), keyUnits: 1)
            cost.append(Cost(), keyUnits: 1)
        case .bool:
            cost.append(text("Bool" as String), keyUnits: 1)
            cost.append(Cost(), keyUnits: 1)
        case .null:
            cost.append(text("Null" as String), keyUnits: 1)
        case .ref(let name), .ph(let name), .stateRef(let name):
            // StateRef is the longest tag in this group, a small conservative
            // allowance that does not require allocating protocolASTValue.
            cost.append(text("StateRef" as String), keyUnits: 1)
            cost.append(text(name), keyUnits: 1)
        case .runtimeRef(let name, let refType):
            cost.append(text("RuntimeRef" as String), keyUnits: 1)
            cost.append(text(name), keyUnits: 1)
            cost.append(text(refType.rawValue), keyUnits: 7)
        case .arr(let values):
            cost.append(text("Arr" as String), keyUnits: 1)
            cost.append(sequence(values, at: depth + 1) { self.ast($0, at: $1) }, keyUnits: 3)
        case .obj(let entries):
            cost.append(text("Obj" as String), keyUnits: 1)
            cost.append(sequence(entries, at: depth + 1) { entry, level in
                guard level < Cost.maximumDepth else { return .oversized }
                var pair = Cost.container
                pair.append(self.text(entry.0))
                pair.append(self.ast(entry.1, at: level + 1))
                return pair
            }, keyUnits: 7)
        case .comp(let name, let args, let mapped, let fn):
            cost.append(text("Comp" as String), keyUnits: 1)
            cost.append(text(name), keyUnits: 4)
            cost.append(sequence(args, at: depth + 1) { self.ast($0, at: $1) }, keyUnits: 4)
            if let mapped {
                cost.append(fields(mapped, at: depth + 1, key: { self.units($0.0) }) {
                    self.ast($0.1, at: $1)
                }, keyUnits: 11)
            }
            if fn { cost.append(Cost(), keyUnits: 2) }
        case .binOp(let op, let left, let right):
            cost.append(text("BinOp" as String), keyUnits: 1)
            cost.append(text(op), keyUnits: 2)
            cost.append(ast(left, at: depth + 1), keyUnits: 4)
            cost.append(ast(right, at: depth + 1), keyUnits: 5)
        case .unaryOp(let op, let operand):
            cost.append(text("UnaryOp" as String), keyUnits: 1)
            cost.append(text(op), keyUnits: 2)
            cost.append(ast(operand, at: depth + 1), keyUnits: 7)
        case .ternary(let condition, let then, let otherwise):
            cost.append(text("Ternary" as String), keyUnits: 1)
            cost.append(ast(condition, at: depth + 1), keyUnits: 4)
            cost.append(ast(then, at: depth + 1), keyUnits: 4)
            cost.append(ast(otherwise, at: depth + 1), keyUnits: 4)
        case .member(let object, let field):
            cost.append(text("Member" as String), keyUnits: 1)
            cost.append(ast(object, at: depth + 1), keyUnits: 3)
            cost.append(text(field), keyUnits: 5)
        case .index(let object, let index):
            cost.append(text("Index" as String), keyUnits: 1)
            cost.append(ast(object, at: depth + 1), keyUnits: 3)
            cost.append(ast(index, at: depth + 1), keyUnits: 5)
        case .assign(let target, let value):
            cost.append(text("Assign" as String), keyUnits: 1)
            cost.append(text(target), keyUnits: 6)
            cost.append(ast(value, at: depth + 1), keyUnits: 5)
        case .runtimeValue(let value):
            cost.append(text("Ref" as String), keyUnits: 1)
            cost.append(Cost.container, keyUnits: 1) // opaque capture token
            cost.append(self.value(value, at: depth + 1))
        }
        return cost
    }
}

/// Raw transport input is counted once as chunks arrive. Expression limits are
/// checked against the shared parser's existing tokens before Pratt recursion.
struct NativeSourceEnvelope {
    private(set) var units = 0
    mutating func append(_ source: String) -> Bool {
        for _ in source.utf16 {
            units += 1
            if units > OpenUIRuntimeBudget.maximumSourceUTF16 { return false }
        }
        return true
    }
}

func expressionExceedsLimits(_ tokens: [Token]) -> Bool {
    var depth = 0, operators = 0
    for token in tokens {
        switch token {
        case .lParen, .lBrack, .lBrace: depth += 1
        case .rParen, .rBrack, .rBrace: depth = max(0, depth - 1)
        case .plus, .minus, .star, .slash, .percent, .not, .and, .or, .eqEq, .notEq, .greater, .less, .greaterEq, .lessEq, .question, .dot:
            operators += 1
        default: break
        }
        if depth > 128 || operators > 256 { return true }
    }
    return false
}

func runtimeBudgetError() -> OpenUIError {
    OpenUIError(source: .runtime, code: .runtimeError,
        message: "Native execution or output budget exceeded.",
        hint: "The last valid prefix remains readable but is not executable. Replace or reset this document to resume.")
}

/// A terminal native operation failure is distinct from an ordinary recoverable
/// expression diagnostic. Keep its first cause without relabeling it as a limit.
enum NativeExecutionFailure: Sendable {
    case budget
    case runtime(OpenUIError)

    var isBudget: Bool {
        if case .budget = self { return true }
        return false
    }
    var error: OpenUIError {
        switch self {
        case .budget: return runtimeBudgetError()
        case .runtime(let error): return error
        }
    }
}

func failedParseResult(preserving previous: ParseResult? = nil, failure: NativeExecutionFailure) -> ParseResult {
    var result = previous ?? ParseResult(root: nil, rootExpression: nil,
        meta: ParseMeta(incomplete: true, unresolved: [], orphaned: [], statementCount: 0, errors: []),
        stateDeclarations: [], queryStatements: [], mutationStatements: [])
    result.nativeFailure = failure
    result.meta.incomplete = true
    result.queryStatements = []; result.mutationStatements = []
    result.meta.errors = [failure.error]
    return result
}

func limitedParseResult(preserving previous: ParseResult? = nil, error: OpenUIError? = nil) -> ParseResult {
    var result = failedParseResult(preserving: previous, failure: .budget)
    result.meta.errors = [error ?? OpenUIError(source: .parser, code: .parseException,
        message: "Native input budget exceeded (1,048,576 UTF-16 units, 100,000 tokens, 4,096 statements, 128 nesting levels or 256 operators per expression).",
        hint: "The last valid prefix remains readable but is not executable. Replace or reset this document to resume.")]
    return result
}
