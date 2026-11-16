import Foundation
import JavaScriptCore

public func createParser(schema: LibrarySchema) -> Parser { CoreParser(schema: schema) }

/// Native input limits and message selection around the shared batch parser.
final class CoreParser: Parser {
    private let core = SharedCore.shared
    private let parser: JSValue

    init(schema: LibrarySchema) {
        let runtime = SharedCore.shared
        parser = runtime.sync {
            runtime.core("createParser", [runtime.json(runtime.schemaJSON(schema)), schema.rootComponent as Any])
        }
    }

    func parse(_ input: String) -> ParseResult {
        core.sync {
            guard OpenUIRuntimeBudget.acceptsSource(input) else { return limitedParseResult() }
            let content = selectLangMessageContent(input)
            guard OpenUIRuntimeBudget.acceptsSource(content) else { return limitedParseResult() }
            let parsed = NativeRuntimeTrace.measure("Parse") {
                parser.invokeMethod("parse", withArguments: [content])!
            }
            return NativeRuntimeTrace.measure("Parse projection") { core.parseResult(parsed) }
        }
    }
}

/// AST construction is performed by the shared TypeScript parser.
public func parseExpression(_ tokens: [Token]) -> ASTNode {
    guard !expressionExceedsLimits(tokens) else { return .null }
    let core = SharedCore.shared
    return core.sync { core.decodeAST(core.core("parseExpression", [core.array(tokens.map { core.token($0) })])) }
}
