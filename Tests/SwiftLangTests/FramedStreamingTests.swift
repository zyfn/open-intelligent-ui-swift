import JavaScriptCore
import XCTest
@testable import SwiftLang

final class FramedStreamingTests: XCTestCase {
    private func schema() -> LibrarySchema {
        LibrarySchema(components: ["Box": [ParamDef(name: "value", required: true)]],
            callDefs: builtinCallDefs, rootComponent: "Box")
    }
    private let retry = "]]>openui:content\nroot=Box(\"old\n]]>openui:content\nroot=Box(\"new\")\n]]>openui:end"

    private func assertEquivalent(_ actual: ParseResult, _ expected: ParseResult,
                                 _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.root, expected.root, message, file: file, line: line)
        XCTAssertEqual(actual.rootExpression, expected.rootExpression, message, file: file, line: line)
        XCTAssertEqual(actual.meta.incomplete, expected.meta.incomplete, message, file: file, line: line)
        XCTAssertEqual(actual.meta.unresolved, expected.meta.unresolved, message, file: file, line: line)
        XCTAssertEqual(actual.meta.orphaned, expected.meta.orphaned, message, file: file, line: line)
        XCTAssertEqual(actual.meta.statementCount, expected.meta.statementCount, message, file: file, line: line)
        XCTAssertEqual(actual.meta.errors.map(\.code), expected.meta.errors.map(\.code), message, file: file, line: line)
        XCTAssertEqual(actual.nativeLimitExceeded, expected.nativeLimitExceeded, message, file: file, line: line)
    }

    /// Direct official extraction and parsing avoid using the native framing
    /// adapter itself as the expected result for partial marker lines.
    private func reference(_ wire: String, complete: Bool) -> ParseResult {
        let core = SharedCore.shared
        return core.sync {
            let schema = schema()
            let parser = core.core("createStreamingParser", [core.json(core.schemaJSON(schema)), schema.rootComponent as Any])
            let content = parseMessage(wire, streaming: !complete).content
            return core.parseResult(parser.invokeMethod("set", withArguments: [content, complete]))
        }
    }

    /// Raw Lang goes directly to the shared parser. Applying parseMessage here
    /// would reproduce the wrapper bug in the expected value as well.
    private func rawReference(_ source: String, complete: Bool) -> ParseResult {
        let core = SharedCore.shared
        return core.sync {
            let schema = schema()
            let parser = core.core("createStreamingParser", [core.json(core.schemaJSON(schema)), schema.rootComponent as Any])
            return core.parseResult(parser.invokeMethod("set", withArguments: [source, complete]))
        }
    }

    func testRawLangCommentAndStringMarkersRemainDataAcrossEverySplit() {
        let examples = [
            "root=Box(\"kept\")\n// ]]>openui:content",
            "root=Box(\"kept\")\r\n# \" ]]>openui:content?retry=2\r\n",
            "// quote \" is comment text\nroot=Box(\"kept\")\n// ]]>openui:end",
            "root=Box(\"😀 上海\n]]>openui:content\nkept\")",
            "root=Box('single\n]]>openui:content\nkept')",
            "root=Box(\"escaped \\\"\n]]>openui:content\nkept\")",
            "root=Box(\"literal ]]>openui:content?retry=2\nkept\")",
            // Retain the original raw fixture, but compare it to raw Lang.
            // At `root=Box("literal ]]>openui:` the old parseMessage oracle
            // incorrectly removed the string's suffix as a potential retry.
            "root=Box(\"literal ]]>openui:end\")",
            "root=Box(\"first\n]]>openui:context\n{not a context}\n]]>openui:end\nlast\")",
            "```openui\nroot=Box(\"kept\")\n// ]]>openui:content\n```",
        ]
        for source in examples {
            let expected = rawReference(source, complete: true)
            XCTAssertNotNil(expected.root, source)
            XCTAssertTrue(expected.meta.errors.isEmpty, source)
            assertEquivalent(createParser(schema: schema()).parse(source), expected, "raw batch")
            assertEquivalent(createStreamingParser(schema: schema()).set(source, complete: true), expected, "raw set")
            let characters = Array(source)
            for width in [1, 2, 7] {
                let parser = createStreamingParser(schema: schema())
                var prefix = ""
                for offset in stride(from: 0, to: characters.count, by: width) {
                    let chunk = String(characters[offset..<min(offset + width, characters.count)])
                    prefix += chunk
                    assertEquivalent(parser.push(chunk), rawReference(prefix, complete: false),
                        "raw width \(width), prefix \(prefix.debugDescription)")
                }
                assertEquivalent(parser.getResult(complete: true), expected, "raw completion")
            }
        }
    }

    func testRealContextAndEndFramesPreserveEarlierRawMarkerText() {
        let prefixes = [
            "root=Box(\"😀\n]]>openui:content\nkept\")\n",
            "root=Box(\"kept\")\r\n// ]]>openui:content\r\n",
        ]
        for prefix in prefixes {
            let expected = rawReference(prefix, complete: true)
            for suffix in ["]]>openui:context\r\n{\"attempt\":1}\r\n]]>openui:end",
                           "]]>openui:end\r\n"] {
                let parser = createStreamingParser(schema: schema())
                parser.set(prefix)
                for character in suffix {
                    let result = parser.push(String(character))
                    XCTAssertEqual(result.root, expected.root, "Partial context/end must keep raw content")
                    XCTAssertTrue(result.meta.errors.isEmpty)
                }
                assertEquivalent(parser.getResult(complete: true), expected, "raw prefix then context/end")
                assertEquivalent(createParser(schema: schema()).parse(prefix + suffix), expected, "batch context/end")
                assertEquivalent(createStreamingParser(schema: schema()).set(prefix + suffix, complete: true), expected, "set context/end")

                // A later real content attempt still wins. It must not recover
                // one of the fake content markers in the earlier raw prefix.
                let retried = parser.push("\n]]>openui:content\nroot=Box(\"new\")", complete: true)
                assertEquivalent(retried, rawReference("root=Box(\"new\")", complete: true), "retry after context/end")
            }
        }
    }

    func testFirstMidlineRetryProtectsRawPrefixAndSupportsBracketOverlap() {
        let raw = "root=Box(\"😀\n]]>openui:content\nkept\")"
        for separator in ["", "]"] {
            let source = raw + separator + "]]>openui:content?attempt=2\r\nroot=Box(\"new\")"
            let expected = rawReference("root=Box(\"new\")", complete: true)
            assertEquivalent(createParser(schema: schema()).parse(source), expected, "midline batch")
            let parser = createStreamingParser(schema: schema())
            for character in source { parser.push(String(character)) }
            assertEquivalent(parser.getResult(complete: true), expected, "midline stream")
        }
    }

    @MainActor func testStateDoesNotEraseRawCommentOrMultilineStringContent() throws {
        for source in ["root=Box(\"kept\")\n// ]]>openui:content",
                       "root=Box(\"😀\n]]>openui:content\nkept\")"] {
            let referenceRoot = try XCTUnwrap(rawReference(source, complete: true).root)
            let referenceProp = try XCTUnwrap(referenceRoot.props.first { $0.key == "value" })
            // The independent parser oracle produces Materialized props;
            // PropValue reads the State's evaluated tree only.
            guard case .value(.string(let referenceText)) = referenceProp.value else {
                return XCTFail("The raw parser reference must contain a string value")
            }
            let expected = referenceText.displayString
            let state = OpenUIState(schema: schema())
            state.setSource(source)
            XCTAssertEqual(PropValue.string(try XCTUnwrap(state.root), "value"), expected)
            XCTAssertTrue(state.errors.isEmpty)
            state.reset()
            for character in source { state.push(String(character)) }
            state.complete()
            XCTAssertEqual(PropValue.string(try XCTUnwrap(state.root), "value"), expected)
            XCTAssertTrue(state.errors.isEmpty)
        }
    }

    func testRetryFramesMatchBatchAcrossChunkBoundaries() {
        let examples = [
            retry,
            "]]>openui:content?v=1\r\nroot=Box(\"old]]>openui:content?v=2\r\nroot=Box(\"new\")\r\n]]>openui:context\r\n{\"attempt\":2}\r\n]]>openui:end\r\n",
            "]]>openui:context\n{\"old\":true}\n]]>openui:content\nroot=Box(\"first\")\n]]>openui:end\n]]>openui:content\nroot=Box(\"new\")\n]]>openui:end"
        ]
        for source in examples {
            let expected = createParser(schema: schema()).parse(source)
            XCTAssertFalse(expected.meta.incomplete)
            XCTAssertTrue(expected.meta.errors.isEmpty)
            let characters = Array(source)
            for width in [1, 7, characters.count] {
                let parser = createStreamingParser(schema: schema())
                for offset in stride(from: 0, to: characters.count, by: width) {
                    parser.push(String(characters[offset..<min(offset + width, characters.count)]))
                }
                assertEquivalent(parser.getResult(complete: true), expected, "chunk width \(width)")
                let set = createStreamingParser(schema: schema()).set(source, complete: true)
                assertEquivalent(set, expected, "set")
            }
        }
    }

    func testPartialMarkerLinesFollowOfficialStreamingSelection() {
        let examples = [retry,
            "]]>openui:content\nroot=Box(\"cut]]>openui:content?v=2\nroot=Box(\"new\")\n]]>openui:end",
            "root=Box([\n[1],\n[2]\n])"]
        for source in examples {
            let parser = createStreamingParser(schema: schema())
            var prefix = ""
            for character in source {
                let chunk = String(character)
                prefix += chunk
                assertEquivalent(parser.push(chunk), reference(prefix, complete: false), "prefix \(prefix.debugDescription)")
            }
            assertEquivalent(parser.getResult(complete: true), reference(source, complete: true), "completion")
        }
        // Completing a held partial line must reconsider it as actual input.
        let partial = "]]>openui:content\nroot=Box(\"kept\")\n]]>open"
        let parser = createStreamingParser(schema: schema())
        assertEquivalent(parser.set(partial), reference(partial, complete: false), "held marker")
        assertEquivalent(parser.getResult(complete: true), reference(partial, complete: true), "unheld marker")
    }

    func testSetThenPushRetainsWireFramesAndReplacementResetsSelection() {
        let characters = Array(retry)
        for boundary in [1, 7, 28, 43, characters.count - 4] {
            let parser = createStreamingParser(schema: schema())
            parser.set(String(characters[..<boundary]))
            let result = parser.push(String(characters[boundary...]), complete: true)
            assertEquivalent(result, createParser(schema: schema()).parse(retry), "boundary \(boundary)")
            let raw = "root=Box(\"raw"
            parser.set(raw)
            let rawResult = parser.push("\")", complete: true)
            assertEquivalent(rawResult, createParser(schema: schema()).parse(raw + "\")"), "replaced raw input")
            // A plain prefix can be followed by a new framed attempt as well.
            let framedAgain = parser.push("\n]]>openui:content\nroot=Box(\"framed\")", complete: true)
            assertEquivalent(framedAgain, createParser(schema: schema()).parse("root=Box(\"framed\")"), "new frame")
        }
    }

    func testParserDoesNotProjectUnusedMessageContext() throws {
        let core = SharedCore.shared
        try core.sync {
            // Count actual context enumeration at the bridge boundary. The
            // shared message parser can return this context without reading
            // its keys; converting it to Swift JSONValue would enumerate it.
            let probe = try XCTUnwrap(core.context.evaluateScript("""
                (() => {
                    const original = JSON.parse;
                    let enumerations = 0;
                    JSON.parse = function(text, ...rest) {
                        const value = original.call(this, text, ...rest);
                        if (value && value.nativeMessageContextProbe === true) {
                            return new Proxy(value, {
                                ownKeys(target) { enumerations++; return Reflect.ownKeys(target); }
                            });
                        }
                        return value;
                    };
                    return {
                        count: () => enumerations,
                        restore: () => { JSON.parse = original; }
                    };
                })()
                """))
            defer { probe.invokeMethod("restore", withArguments: []) }
            let wire = "]]>openui:content\nroot=Box(\"kept\")\n"
                + "]]>openui:context\n{\"nativeMessageContextProbe\":true,\"items\":[1,2,3]}"
            let batch = createParser(schema: schema()).parse(wire)
            let stream = createStreamingParser(schema: schema())
            let first = stream.set(wire)
            let final = stream.push("\n", complete: true)
            for result in [batch, first, final] {
                XCTAssertNotNil(result.root)
                XCTAssertTrue(result.meta.errors.isEmpty)
            }
            XCTAssertEqual(probe.invokeMethod("count", withArguments: []).toInt32(), 0,
                "Parsing Lang must not enumerate unused message context")

            let message = parseMessage(wire)
            XCTAssertEqual(message.context.field("nativeMessageContextProbe"), .boolean(true))
            XCTAssertEqual(message.context.field("items"), .array([.number(1), .number(2), .number(3)]))
            XCTAssertGreaterThan(probe.invokeMethod("count", withArguments: []).toInt32(), 0,
                "The public message API must still project and return its context")
        }
    }

    func testDiscardedFramesStillCountTowardRawUTF16Budget() {
        let header = "]]>openui:context\n", tail = "\n]]>openui:content\nroot=Box(\"kept\")"
        let room = OpenUIRuntimeBudget.maximumSourceUTF16 - header.utf16.count - tail.utf16.count
        let wire = header + String(repeating: "😀", count: room / 2) + String(repeating: " ", count: room % 2) + tail
        XCTAssertEqual(wire.utf16.count, OpenUIRuntimeBudget.maximumSourceUTF16)
        let parser = createStreamingParser(schema: schema())
        let valid = parser.set(wire)
        XCTAssertFalse(valid.nativeLimitExceeded)
        XCTAssertNotNil(valid.root)
        let rejected = parser.push("😀", complete: true)
        XCTAssertTrue(rejected.nativeLimitExceeded)
        XCTAssertEqual(rejected.root, valid.root)
        XCTAssertTrue(parser.getResult(complete: true).nativeLimitExceeded)
        XCTAssertTrue(createStreamingParser(schema: schema()).push(wire + "x", complete: true).nativeLimitExceeded)
        let reset = parser.set("root=Box(\"reset\")", complete: true)
        XCTAssertFalse(reset.nativeLimitExceeded)
        assertEquivalent(reset, createParser(schema: schema()).parse("root=Box(\"reset\")"), "budget reset")
    }

    func testMaterializationLimitPreservesLastPrefixUntilExplicitReplacement() {
        let parser = createStreamingParser(schema: schema())
        let previous = parser.push("root=Box(\"kept\")\n")
        var lines = ["leaf=Box(\"leaf\")"]
        for level in 0..<13 {
            let child = level == 0 ? "leaf" : "node\(level - 1)"
            lines.append("node\(level)=Box([\(child),\(child)])")
        }
        lines.append("root=node12")
        let rejected = parser.push(lines.joined(separator: "\n"), complete: true)
        XCTAssertTrue(rejected.nativeLimitExceeded)
        XCTAssertEqual(rejected.root, previous.root)
        XCTAssertTrue(rejected.meta.errors.contains { $0.message.contains("materialization") })
        let ignored = parser.push("\n]]>openui:content\nroot=Box(\"later\")", complete: true)
        XCTAssertTrue(ignored.nativeLimitExceeded)
        XCTAssertEqual(ignored.root, previous.root)
        XCTAssertEqual(ignored.meta.errors.map(\.message), rejected.meta.errors.map(\.message))
        XCTAssertTrue(parser.getResult(complete: true).nativeLimitExceeded)
        let replacement = parser.set("root=Box(\"replacement\")", complete: true)
        XCTAssertFalse(replacement.nativeLimitExceeded)
        assertEquivalent(replacement, createParser(schema: schema()).parse("root=Box(\"replacement\")"), "explicit replacement")
    }

    @MainActor func testStatePushAndGrowingBuffersUseTheSameWinningFrame() throws {
        for useGrowingBuffer in [false, true] {
            let state = OpenUIState(schema: schema())
            var buffer = ""
            for character in retry {
                let chunk = String(character)
                buffer += chunk
                if useGrowingBuffer { state.setSource(buffer, streaming: true) }
                else { state.push(chunk) }
            }
            state.complete()
            XCTAssertEqual(PropValue.string(try XCTUnwrap(state.root), "value"), "new")
            XCTAssertTrue(state.errors.isEmpty)
            state.reset()
            state.push("root=Box(\"raw\")")
            state.complete()
            XCTAssertEqual(PropValue.string(try XCTUnwrap(state.root), "value"), "raw")
        }
    }
}
