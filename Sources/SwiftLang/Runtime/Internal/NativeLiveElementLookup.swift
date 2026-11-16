/// Resolves an older immutable projection against one indexed document.
/// Readiness ambiguity and language-value equality retain their existing rules.
func nativeResolveLiveElement(_ element: EvaluatedElement, in index: NativeLiveElementIndex) -> EvaluatedElement {
    if index.contains(element) { return element }
    func same(_ a: Value, _ b: Value, depth: Int) -> Bool {
        guard depth < 256 else { return false }
        switch (a,b) {
        case (.element(let x), .element(let y)):
            return x.typeName == y.typeName && x.statementId == y.statementId && props(x,y,depth:depth+1)
        case (.array(let x), .array(let y)):
            return x.count == y.count && zip(x,y).allSatisfy { same($0,$1,depth:depth+1) }
        case (.object(let x), .object(let y)):
            return x.count == y.count && zip(x,y).allSatisfy { $0.key == $1.key && same($0.value,$1.value,depth:depth+1) }
        default: return a == b
        }
    }
    func props(_ x: EvaluatedElement, _ y: EvaluatedElement, depth: Int) -> Bool {
        x.props.count == y.props.count && zip(x.props,y.props).allSatisfy {
            $0.0 == $1.0 && same($0.1,$1.1,depth:depth+1)
        }
    }
    // A stable native child may hold an earlier readiness snapshot even
    // when its displayed props have not changed. Match nested values too;
    // never borrow readiness from a semantically different control.
    let matches = index.candidates(for: element).filter {
        props($0, element, depth: 0)
    }
    func readiness(_ a: Value, _ b: Value, depth: Int) -> Bool {
        guard depth < 256 else { return false }
        switch (a, b) {
        case (.element(let x), .element(let y)): return metadata(x, y, depth: depth + 1)
        case (.actionPlan(let x), .actionPlan(let y)): return x.isSourceComplete == y.isSourceComplete
        case (.array(let x), .array(let y)):
            return x.count == y.count && zip(x,y).allSatisfy { readiness($0,$1,depth:depth+1) }
        case (.object(let x), .object(let y)):
            return x.count == y.count && zip(x,y).allSatisfy { readiness($0.value,$1.value,depth:depth+1) }
        default: return true
        }
    }
    func metadata(_ x: EvaluatedElement, _ y: EvaluatedElement, depth: Int) -> Bool {
        x.isSourceComplete == y.isSourceComplete && x.sourceReadiness == y.sourceReadiness && x.props.count == y.props.count
            && zip(x.props,y.props).allSatisfy { readiness($0.1,$1.1,depth:depth+1) }
    }
    let current = matches.first.flatMap { first in
        matches.allSatisfy { metadata(first,$0,depth:0) } ? first : nil
    } ?? element
    return current
}
