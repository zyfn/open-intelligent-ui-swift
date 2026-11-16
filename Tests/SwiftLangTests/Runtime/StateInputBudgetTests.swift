import XCTest
@testable import SwiftLang

final class StateInputBudgetTests: XCTestCase {
    private func schema() -> LibrarySchema {
        LibrarySchema(components: ["Box": [ParamDef(name: "value", required: true)]], callDefs: builtinCallDefs)
    }

    @MainActor func testOversizedStateWriteKeepsThePreviousStoreAndPresentation() throws {
        let state = OpenUIState(schema: schema())
        state.setSource("$value=7\nroot=Box($value)")
        var updates = 0
        state.onStateUpdate = { _ in updates += 1 }
        state.setState("$value", value: deepValue())
        XCTAssertEqual(state.stateValue("$value"), .number(7), "Reject before Store encodes or commits the new value")
        XCTAssertEqual(PropValue.value(try XCTUnwrap(state.root), "value"), .number(7))
        XCTAssertEqual(updates, 0)
        XCTAssertTrue(state.isInterrupted)
        XCTAssertFalse(state.canExecuteActions)
        XCTAssertFalse(state.errors.isEmpty)
    }

    @MainActor func testInitialPersistedStateUsesAnAggregateBudgetAndCanReset() throws {
        let values = overBudgetState()
        XCTAssertTrue(values.values.allSatisfy { !nativeValueExceedsLimits($0) },
            "Each field fits separately; the combined persisted graph is too large")
        let state = OpenUIState(schema: schema(), persistedState: values)
        state.setSource("root=Box(\"initial\")")
        XCTAssertTrue(state.isInterrupted)
        XCTAssertFalse(state.canExecuteActions)
        XCTAssertFalse(state.errors.isEmpty)
        XCTAssertNil(state.root)
        XCTAssertTrue(state.snapshotState().isEmpty)
        state.reset()
        state.setSource("$value=2\nroot=Box($value)")
        XCTAssertEqual(PropValue.value(try XCTUnwrap(state.root), "value"), .number(2))
        XCTAssertTrue(state.canExecuteActions)
        XCTAssertFalse(state.isInterrupted)
        XCTAssertTrue(state.errors.isEmpty)
    }

    @MainActor func testOversizedRestoreDoesNotPartiallyOverwriteTheCurrentState() throws {
        let state = OpenUIState(schema: schema())
        state.setSource("$value=7\nroot=Box($value)")
        var incoming = overBudgetState()
        incoming["$value"] = .number(99)
        state.restoreState(incoming)
        XCTAssertEqual(state.stateValue("$value"), .number(7))
        XCTAssertEqual(PropValue.value(try XCTUnwrap(state.root), "value"), .number(7))
        XCTAssertNil(state.snapshotState()["$first"])
        XCTAssertTrue(state.isInterrupted)
        XCTAssertFalse(state.canExecuteActions)
        state.setSource("$value=3\nroot=Box($value)")
        XCTAssertEqual(PropValue.value(try XCTUnwrap(state.root), "value"), .number(3),
            "A rejected restoration must not remain pending in the replacement document")
        XCTAssertTrue(state.canExecuteActions)
    }

    private func overBudgetState() -> [OpenUIString: Value] {
        let shared = Value.array(Array(repeating: .number(1), count: 60_000))
        return ["$first": shared, "$second": shared]
    }

    private func deepValue() -> Value {
        var value = Value.number(1)
        for _ in 0..<300 { value = .array([value]) }
        return value
    }
}
