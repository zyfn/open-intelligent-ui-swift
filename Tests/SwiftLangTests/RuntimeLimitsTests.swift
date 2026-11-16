import XCTest
@testable import SwiftLang

final class RuntimeLimitsTests: XCTestCase {
    func testSourceBudgetPreservesOperatorAndDepthBoundaries() {
        let parser = createParser(schema: ParserSmokeTests().makeSchema())
        // Keep the expression unreferenced so this measures the source guard,
        // independently of the later materialization/output depth budget.
        let prefix = "root=Text(\"ready\")\nunused="
        XCTAssertFalse(parser.parse(prefix + Array(repeating: "1", count: 257).joined(separator: "+")).nativeLimitExceeded)
        XCTAssertTrue(parser.parse(prefix + Array(repeating: "1", count: 258).joined(separator: "+")).nativeLimitExceeded)
        XCTAssertFalse(parser.parse(prefix + String(repeating: "[", count: 128) + "1" + String(repeating: "]", count: 128)).nativeLimitExceeded)
        XCTAssertTrue(parser.parse(prefix + String(repeating: "[", count: 129) + "1").nativeLimitExceeded)
    }

    func testSourceBudgetMatchesTheExistingTokenGuard() {
        // The removed standalone source preflight now lives in the parser.
        // Keep the independent native token guard as the oracle and verify the
        // real parser result, rather than retaining a second production path.
        let expressions = [
            "root=Text(\"++++[[[ punctuation is text\")",
            "$value=1\nroot=Text(\"value\")",
            "root=Stack([Text(\"unfinished",
            "root=1?2:3\nnext=" + Array(repeating: "1", count: 258).joined(separator: "+"),
        ]
        let parser = createParser(schema: ParserSmokeTests().makeSchema())
        for source in expressions {
            let reference = splitStatements(tokenize(source)).contains { expressionExceedsLimits($0.tokens) }
            XCTAssertEqual(parser.parse(source).nativeLimitExceeded, reference, source)
        }
    }
    func testGuardIgnoresCommentsAndFencesLikeTheSharedParser() {
        let schema = ParserSmokeTests().makeSchema()
        let source = "root=Stack([Text(\"https://example.test/#place\")])"
        let symbols = String(repeating: "+", count: 260)
        for marker in ["#", "//"] {
            let text = source + " " + marker + symbols
            let batch = createParser(schema: schema).parse(text)
            XCTAssertFalse(batch.nativeLimitExceeded, "Comment content is not an expression")
            XCTAssertNotNil(batch.root)
            XCTAssertTrue(batch.meta.errors.isEmpty, "\(batch.meta.errors)")
            let stream = createStreamingParser(schema: schema)
            _ = stream.push(source + " " + marker)
            let partial = stream.push(symbols)
            XCTAssertTrue(partial.meta.errors.isEmpty, "Comments arriving in a stream must stay comments")
            let final = stream.push("\n", complete: true)
            XCTAssertNotNil(final.root)
            XCTAssertTrue(final.meta.errors.isEmpty, "\(final.meta.errors)")
        }
        let fenced = "```openui-lang\n" + source + " #" + symbols + "\n```"
        XCTAssertFalse(createParser(schema: schema).parse(fenced).nativeLimitExceeded)
        XCTAssertTrue(createParser(schema: schema).parse(fenced).meta.errors.isEmpty)
        XCTAssertTrue(createParser(schema: schema).parse("root=" + Array(repeating: "1", count: 258).joined(separator: "+")).nativeLimitExceeded)
    }

    func testGuardUsesTheSameSelectedMessageContentAsBatchAndStreamSet() {
        let schema = ParserSmokeTests().makeSchema()
        let prior = "root=" + Array(repeating: "1", count: 258).joined(separator: "+")
        let current = "root=Stack([Text(\"Latest\")])"
        let wire = "]]>openui:content\n" + prior + "\n]]>openui:content\n" + current + "\n]]>openui:end"
        XCTAssertEqual(parseMessage(wire).content.trimmingCharacters(in: .whitespacesAndNewlines), current)
        let batch = createParser(schema: schema).parse(wire)
        XCTAssertNotNil(batch.root)
        XCTAssertTrue(batch.meta.errors.isEmpty, "\(batch.meta.errors)")
        let stream = createStreamingParser(schema: schema)
        let snapshot = stream.set(wire, complete: false)
        XCTAssertNotNil(snapshot.root)
        XCTAssertTrue(snapshot.meta.errors.isEmpty, "\(snapshot.meta.errors)")
        let appended = stream.push("\n", complete: true)
        XCTAssertNotNil(appended.root)
        XCTAssertTrue(appended.meta.errors.isEmpty, "\(appended.meta.errors)")
    }

    func testStreamingDeclarationBudgetCountsDuplicatesAndPreservesLastGoodUntilReplacement() {
        let schema = ParserSmokeTests().makeSchema()
        let source = "root=Text(\"ready\")\n" + String(repeating: "same=0\n", count: 4095)
        XCTAssertFalse(createParser(schema: schema).parse(source).nativeLimitExceeded)
        let stream = createStreamingParser(schema: schema)
        let boundary = stream.set(source, complete: true)
        XCTAssertFalse(boundary.nativeLimitExceeded)
        for _ in 0..<4 { XCTAssertFalse(stream.getResult().nativeLimitExceeded) }
        let rejected = stream.push("same=1\n")
        XCTAssertTrue(rejected.nativeLimitExceeded)
        XCTAssertEqual(rejected.root, boundary.root, "A failed append keeps the last accepted prefix")
        XCTAssertTrue(stream.push("root=Text(\"late\")\n").nativeLimitExceeded)
        let replacement = stream.set("root=Text(\"recovered\")\n", complete: true)
        XCTAssertFalse(replacement.nativeLimitExceeded)
        XCTAssertFalse(stream.push("same=1\n", complete: true).nativeLimitExceeded)
    }

    func testStreamingSourceBudgetResetsWhenFencesReplaceThePreviouslyCompletedPrefix() {
        let stream = createStreamingParser(schema: ParserSmokeTests().makeSchema())
        XCTAssertFalse(stream.push("root=Text(\"before\")\n" + String(repeating: "same=0\n", count: 4094)).nativeLimitExceeded)
        XCTAssertFalse(stream.push("```openui\nroot=Text(\"after\")\n").nativeLimitExceeded)
        XCTAssertFalse(stream.push(String(repeating: "same=0\n", count: 4095)).nativeLimitExceeded)
        XCTAssertTrue(stream.push("same=1\n").nativeLimitExceeded)
        XCTAssertFalse(stream.set("root=Text(\"recovered\")", complete: true).nativeLimitExceeded)
    }

    func testTokenBudgetCountsCompletedStatementsAndPendingTailWithoutDoubleCharging() {
        let schema = ParserSmokeTests().makeSchema()
        func array(_ count: Int) -> String { "[" + Array(repeating: "0", count: count).joined(separator: ",") + "]" }
        let source = "root=Text(\"ready\")\n" + String(repeating: "same=" + array(200) + "\n", count: 249) + "same=" + array(73)
        let stream = createStreamingParser(schema: schema)
        XCTAssertFalse(createParser(schema: schema).parse(source).nativeLimitExceeded)
        XCTAssertFalse(stream.set(String(source.dropLast())).nativeLimitExceeded)
        for _ in 0..<4 { XCTAssertFalse(stream.getResult().nativeLimitExceeded) }
        let boundary = stream.push("]", complete: true)
        XCTAssertFalse(boundary.nativeLimitExceeded)
        let rejected = stream.push("\nextra=0", complete: true)
        XCTAssertTrue(rejected.nativeLimitExceeded)
        XCTAssertEqual(rejected.root, boundary.root)
    }

}
