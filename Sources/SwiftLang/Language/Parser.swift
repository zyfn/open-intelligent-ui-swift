import Foundation

/// AST construction is performed by the shared TypeScript parser.
public func parseExpression(_ tokens: [Token]) -> ASTNode {
    guard !expressionExceedsLimits(tokens) else { return .null }
    let core = SharedCore.shared
    return core.sync { core.decodeAST(core.core("parseExpression", [core.array(tokens.map { core.token($0) })])) }
}
func emptyParseResult(incomplete: Bool = true) -> ParseResult {
    ParseResult(root: nil, rootExpression: nil, meta: ParseMeta(incomplete: incomplete, unresolved: [], orphaned: [], statementCount: 0, errors: []), stateDeclarations: [], queryStatements: [], mutationStatements: [])
}
func stripMessageMarkers(_ text: String) -> String {
    var probe = MessageProbe()
    probe.append(text)
    guard let prefix = probe.protectedPrefix(complete: true) else { return text }
    return parseMessageContent(text, protectedPrefix: prefix)
}
