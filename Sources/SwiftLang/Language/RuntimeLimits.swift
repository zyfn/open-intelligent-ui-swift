// Bounded recursive work: model output must not exhaust the native call stack.
import Foundation
import JavaScriptCore

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
    NativeValueBudget().value(value, at: 0).exceeds
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
    NativeValueBudget().expression(node).exceeds
}

private struct NativeValueCost {
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
    func expression(_ node: ASTNode) -> Cost { ast(node, at: 0) }
    func value(_ value: Value, at depth: Int) -> Cost {
        guard visit() else { return .oversized }
        switch value {
        case .string(let string): return text(string)
        case .number, .boolean, .null, .undefined: return Cost()
        case .array(let array):
            return reference(array, at: depth) {
                sequence(array, at: depth) { self.value($0, at: $1) }
            }
        case .object(let object):
            return reference(object, at: depth) {
                var hasElementMarker = false
                var cost = fields(object, at: depth, key: { $0.key.count }) { field, level in
                    if field.key == "type", case .string(let type) = field.value, type == "element" {
                        hasElementMarker = true
                    }
                    return self.value(field.value, at: level)
                }
                // The JS output guard also counts plain objects with this
                // marker, without interpreting them as a native component.
                if hasElementMarker { cost.elements = min(Cost.maximumElements + 1, cost.elements + 1) }
                return cost
            }
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

/// Raw counts are conservative upper bounds: quoted/comment punctuation can
/// cause an extra guard pass, never bypass a real expression limit.
struct NativeSourceEnvelope {
    private(set) var units = 0
    private var openings = 0
    private var operators = 0
    var triviallySafe: Bool { units <= 100_000 && openings <= 128 && operators <= 256 }
    mutating func append(_ source: String) -> Bool {
        for unit in source.utf16 {
            units += 1
            if units > OpenUIRuntimeBudget.maximumSourceUTF16 { return false }
            switch unit {
            case 40, 91, 123: openings += 1
            case 46, 43, 45, 42, 47, 37, 33, 38, 124, 61, 62, 60, 63: operators += 1
            default: break
            }
        }
        return true
    }
}

/// Keep token inspection inside the same realm as the shared lexer. Previously
/// every string token was decoded to Swift merely to count its discriminant.
private enum NativeExpressionGuard {
    static let check = SharedCore.shared.sync {
        let core = SharedCore.shared
        func kinds(_ tokens: [Token]) -> String {
            tokens.map { String(core.token($0).forProperty("t").toInt32()) }.joined(separator: ",")
        }
        let openings = kinds([.lParen, .lBrack, .lBrace])
        let closings = kinds([.rParen, .rBrack, .rBrace])
        let operators = kinds([.plus, .minus, .star, .slash, .percent, .not, .and, .or,
            .eqEq, .notEq, .greater, .less, .greaterEq, .lessEq, .question, .dot])
        return core.context.evaluateScript("""
          (function(statements) {
            const opens = new Set([\(openings)]), closes = new Set([\(closings)]), ops = new Set([\(operators)]);
            if (statements.length > 4096) return true;
            let total = 0;
            for (const statement of statements) {
              let depth = 0, operators = 0;
              for (const token of statement.tokens) {
                if (++total > 100000) return true;
                if (opens.has(token.t)) depth++;
                else if (closes.has(token.t)) depth = Math.max(0, depth - 1);
                else if (ops.has(token.t)) operators++;
                if (depth > 128 || operators > 256) return true;
              }
            }
            return false;
          })
          """)!
    }
}

func sourceExceedsLimits(_ source: String) -> Bool {
    var envelope = NativeSourceEnvelope()
    guard envelope.append(source) else { return true }
    if envelope.triviallySafe { return false }
    return expressionSourceExceedsLimits(source)
}

func expressionSourceExceedsLimits(_ source: String) -> Bool {
    let core = SharedCore.shared
    return core.sync {
        let cleaned = core.call("preprocess", [source])
        let tokens = core.core("tokenize", [cleaned])
        let statements = core.core("split", [tokens])
        let result = NativeExpressionGuard.check.call(withArguments: [statements])
        if core.context.exception != nil { core.context.exception = nil; return true }
        return result?.toBool() ?? true
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

func limitedParseResult(preserving previous: ParseResult? = nil, error: OpenUIError? = nil) -> ParseResult {
    var result = previous ?? emptyParseResult(incomplete: true)
    result.nativeLimitExceeded = true
    result.meta.incomplete = true
    result.queryStatements = []; result.mutationStatements = []
    result.meta.errors = [error ?? OpenUIError(source: .parser, code: .parseException,
        message: "Native input budget exceeded (1,048,576 UTF-16 units, 100,000 tokens, 4,096 statements, 128 nesting levels or 256 operators per expression).",
        hint: "The last valid prefix remains readable but is not executable. Replace or reset this document to resume.")]
    return result
}
