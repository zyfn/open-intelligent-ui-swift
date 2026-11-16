import Combine
import XCTest
@testable import SwiftLang

final class StreamingPublicationTests: XCTestCase {
    private var schema: LibrarySchema {
        LibrarySchema(components: [
            "Stack": [ParamDef(name: "children", required: true)],
            "Box": [ParamDef(name: "value", required: true)]
        ], callDefs: builtinCallDefs)
    }

    @MainActor func testChangingTailPublishesOncePerPushWithoutDeferringTextOrReadiness() throws {
        let state = OpenUIState(schema: schema)
        defer { state.reset() }
        state.push("root=Stack([fixed,tail])\nfixed=Box(\"fixed\")\ntail=Box(\"")
        var publications = 0, parses = 0
        let changes = state.objectWillChange.sink { publications += 1 }
        defer { changes.cancel() }
        state.onParseResult = { _ in parses += 1 }
        var expected = ""
        for chunk in ["SHANGHAI →", " SUZHOU", " · 2 DAYS", " · 3 位成人"] {
            expected += chunk
            let before = publications
            state.push(chunk)
            XCTAssertEqual(publications - before, 1,
                "One input must not broadcast separate root and readiness updates")
            let children = PropValue.children(try XCTUnwrap(state.root))
            XCTAssertEqual(PropValue.string(try XCTUnwrap(children.first), "value"), "fixed")
            XCTAssertEqual(PropValue.string(try XCTUnwrap(children.last), "value"), expected,
                "The whole received prefix is visible before push returns")
        }
        let beforeClose = publications
        let pending = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).last)
        XCTAssertFalse(pending.sourceReadiness.closed)
        state.push("\")")
        let closed = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).last)
        XCTAssertEqual(publications - beforeClose, 1)
        XCTAssertEqual(PropValue.string(closed, "value"), expected)
        XCTAssertTrue(closed.sourceReadiness.closed,
            "A delimiter-only update must still publish its new readiness")
        XCTAssertEqual(parses, 5)
        XCTAssertFalse(state.isComplete)
        state.complete()
        XCTAssertTrue(state.isComplete)
        XCTAssertTrue(state.canExecuteActions)
        XCTAssertEqual(parses, 6)
    }

    @MainActor func testRootSubscriberSeesTheCompanionReadinessOfTheIncomingSnapshot() throws {
        let state = OpenUIState(schema: schema)
        defer { state.reset() }
        state.push("root=Box(\"ready")
        var observedClosed: [Bool] = []
        let roots = state.$root.dropFirst().sink { _ in
            observedClosed.append(state.presentationRoot?.closed ?? false)
        }
        defer { roots.cancel() }
        state.push("\")")
        XCTAssertEqual(observedClosed, [true])
        XCTAssertEqual(PropValue.string(try XCTUnwrap(state.root), "value"), "ready")
        state.reset()
        XCTAssertNil(state.root)
        XCTAssertNil(state.presentationRoot)
    }
}
