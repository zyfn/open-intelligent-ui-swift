import XCTest
@testable import SwiftLang

final class PatchBudgetTests: XCTestCase {
    private func schema() -> LibrarySchema {
        LibrarySchema(components: ["Box": [ParamDef(name: "value", required: true)]], callDefs: builtinCallDefs)
    }

    @MainActor func testOversizedRawPatchKeepsTheLastPresentationAndStoreThenAllowsReplacement() throws {
        let state = OpenUIState(schema: schema())
        defer { state.reset() }
        state.setSource("$value=7\nroot=Box($value)")
        state.setState("$value", value: .number(9))
        let previous = try XCTUnwrap(state.root)
        let presentationRevision = state.presentationRevision
        var reports = 0, stateUpdates = 0
        state.onError = { _ in reports += 1 }
        state.onStateUpdate = { _ in stateUpdates += 1 }

        state.applyPatch(String(repeating: " ", count: 2 * OpenUIRuntimeBudget.maximumSourceUTF16)
            + "$value=99\nroot=Box(\"after\")")

        XCTAssertTrue(state.root === previous)
        XCTAssertEqual(state.stateValue("$value"), .number(9))
        XCTAssertEqual(state.presentationRevision, presentationRevision)
        XCTAssertEqual(stateUpdates, 0)
        XCTAssertEqual(reports, 1)
        XCTAssertTrue(state.isInterrupted)
        XCTAssertTrue(state.isComplete)
        XCTAssertFalse(state.canExecuteActions)
        XCTAssertEqual(state.errors.first?.code, .runtimeError)

        state.setSource("root=Box(\"recovered\")")
        XCTAssertEqual(PropValue.string(try XCTUnwrap(state.root), "value"), "recovered")
        XCTAssertFalse(state.isInterrupted)
        XCTAssertTrue(state.errors.isEmpty)
        XCTAssertTrue(state.canExecuteActions)
    }

    @MainActor func testCumulativeMergeWorkCannotCommitDeletedStateOrANewRoot() throws {
        let state = OpenUIState(schema: schema())
        defer { state.reset() }
        let declarations = (0..<1_000).map { "$v\($0)=0" }
        let deletions = (0..<1_000).map { "$v\($0)=null" }
        state.setSource((["root=Box(\"before\")"] + declarations).joined(separator: "\n"))
        XCTAssertTrue(state.canExecuteActions)
        let previous = try XCTUnwrap(state.root)
        let values = state.snapshotState()
        XCTAssertEqual(values.count, 1_000)

        state.applyPatch((["root=Box(\"after\")"] + deletions).joined(separator: "\n"))

        XCTAssertTrue(state.root === previous)
        XCTAssertEqual(state.snapshotState(), values)
        XCTAssertTrue(state.isInterrupted)
        XCTAssertFalse(state.canExecuteActions)
        XCTAssertFalse(state.errors.isEmpty)
        state.reset()
        state.setSource("root=Box(\"recovered\")")
        XCTAssertEqual(PropValue.string(try XCTUnwrap(state.root), "value"), "recovered")
        XCTAssertTrue(state.canExecuteActions)
        XCTAssertTrue(state.errors.isEmpty)
    }

    @MainActor func testPatchDuringAnUnfinishedStreamIsStillIgnored() throws {
        let state = OpenUIState(schema: schema())
        defer { state.reset() }
        state.push("root=Box(\"before\")")
        state.applyPatch(String(repeating: " ", count: OpenUIRuntimeBudget.maximumSourceUTF16 + 1))
        XCTAssertFalse(state.isInterrupted)
        XCTAssertTrue(state.errors.isEmpty)
        state.complete()
        XCTAssertEqual(PropValue.string(try XCTUnwrap(state.root), "value"), "before")
        XCTAssertTrue(state.canExecuteActions)
    }

    @MainActor func testErrorCallbackReplacementCannotBeOverwrittenByFailedPatch() throws {
        let state = OpenUIState(schema: schema())
        defer { state.reset() }
        state.setSource("root=Box(\"before\")")
        var reports = 0
        state.onError = { [weak state] errors in
            guard !errors.isEmpty else { return }
            reports += 1
            state?.setSource("root=Box(\"replacement\")")
        }
        state.applyPatch(String(repeating: " ", count: OpenUIRuntimeBudget.maximumSourceUTF16 + 1)
            + "root=Box(\"must not commit\")")
        XCTAssertEqual(reports, 1)
        XCTAssertEqual(PropValue.string(try XCTUnwrap(state.root), "value"), "replacement")
        XCTAssertTrue(state.canExecuteActions)
        XCTAssertFalse(state.isInterrupted)
        XCTAssertTrue(state.errors.isEmpty)
    }
}
