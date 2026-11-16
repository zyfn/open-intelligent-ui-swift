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

    @MainActor func testSeparateAcceptedWritesCannotAccumulateAnUnrestorableSnapshot() throws {
        let state = OpenUIState(schema: schema())
        state.setSource("root=Box(\"ready\")")
        let shared = Value.array(Array(repeating: .number(1), count: 60_000))
        state.setState("$first", value: shared)
        XCTAssertTrue(state.canExecuteActions)
        let accepted = state.snapshotState()
        XCTAssertEqual(accepted["$first"], shared)
        XCTAssertFalse(nativeStateExceedsLimits(accepted))
        let root = try XCTUnwrap(state.root)
        var updates = 0
        state.onStateUpdate = { _ in updates += 1 }

        state.setState("$second", value: shared)
        XCTAssertNil(state.snapshotState()["$second"], "Charge every retained occurrence before committing the second field")
        XCTAssertEqual(state.snapshotState()["$first"], shared)
        XCTAssertEqual(updates, 0)
        XCTAssertTrue(state.root === root)
        XCTAssertTrue(state.isInterrupted)
        XCTAssertFalse(nativeStateExceedsLimits(state.snapshotState()))

        let restored = OpenUIState(schema: schema(), persistedState: state.snapshotState())
        restored.setSource("root=Box(\"restored\")")
        XCTAssertTrue(restored.canExecuteActions)
        XCTAssertTrue(restored.errors.isEmpty)
        XCTAssertEqual(restored.snapshotState(), accepted)
    }

    @MainActor func testReplacingAFieldReturnsItsBudgetAndKeepsUTF16DistinctKeys() {
        let state = OpenUIState(schema: schema())
        state.setSource("root=Box(\"ready\")")
        let large = Value.array(Array(repeating: .number(1), count: 60_000))
        let small = Value.array(Array(repeating: .number(2), count: 30_000))
        state.setState("$\u{00E9}", value: large)
        state.setState("$\u{00E9}", value: large)
        XCTAssertTrue(state.canExecuteActions, "A replacement does not add another copy to the state budget")
        state.setState("$\u{00E9}", value: small)
        state.setState("$e\u{0301}", value: large)
        XCTAssertTrue(state.canExecuteActions)
        XCTAssertEqual(state.snapshotState().count, 2)
        XCTAssertEqual(state.stateValue("$\u{00E9}"), small)
        XCTAssertEqual(state.stateValue("$e\u{0301}"), large)
        XCTAssertFalse(nativeStateExceedsLimits(state.snapshotState()))
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
