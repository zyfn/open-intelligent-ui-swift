import JavaScriptCore
import XCTest
@testable import SwiftLang

final class QuerySnapshotBridgeTests: XCTestCase {
    private func request(_ id: String, tool: String = "load", defaults: Value = .null) -> QueryStatementInfo {
        QueryStatementInfo(statementId: id, toolAST: .str(OpenUIString(tool)), argsAST: .obj([]),
            defaultsAST: .runtimeValue(defaults), refreshAST: nil, deps: nil, complete: true)
    }

    private func synchronize(_ manager: QueryManager, _ statements: [QueryStatementInfo]) {
        let context = EvaluationContext(getState: { _ in .null }, resolveRef: { _ in .null })
        manager.evaluateStatements(statements, evaluator: Evaluator(context: context, schema: LibrarySchema()))
    }

    func testBatchPreservesMissingUndefinedAndSharedDefaultIdentity() throws {
        let manager = QueryManager(provider: nil)
        defer { manager.dispose() }
        let shared = Value.object([.init(key: "title", value: .string("上海"))])
        synchronize(manager, [request("a", defaults: shared), request("b", defaults: shared),
                              request("undefined", defaults: .undefined), request("null")])
        let states = manager.queryStates(for: ["b", "a", "b", "missing", "undefined", "null"])
        XCTAssertEqual(states.count, 4)
        XCTAssertNil(states["missing"])
        XCTAssertNil(manager.queryState(for: "missing"))
        XCTAssertEqual(states["undefined"]?.data, .undefined)
        XCTAssertEqual(states["null"]?.data, .null)
        XCTAssertEqual(states["a"]?.status, .idle)
        XCTAssertTrue(try XCTUnwrap(states["a"]?.data).isSameValue(as: shared))
        XCTAssertTrue(try XCTUnwrap(states["b"]?.data).isSameValue(as: shared))
        XCTAssertEqual(manager.queryState(for: "a")?.data, states["a"]?.data)
    }

    func testBatchDoesNotRetainErrorsAcrossQueryReplacementOrDisposal() async throws {
        let manager = QueryManager(tools: ["ok": { _ in .number(42) }])
        defer { manager.dispose() }
        synchronize(manager, [request("a", tool: "missing-one", defaults: .string("first")),
                              request("b", tool: "missing-two", defaults: .string("second"))])
        for _ in 0..<300 {
            let states = manager.queryStates(for: ["a", "b"])
            if states["a"]?.status == .error && states["b"]?.status == .error { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let failed = manager.queryStates(for: ["b", "a"])
        for (id, tool, expected) in [("a", "missing-one", "first"), ("b", "missing-two", "second")] {
            let state = try XCTUnwrap(failed[id])
            XCTAssertEqual(state.status, .error)
            XCTAssertEqual(state.data, .string(OpenUIString(expected)))
            XCTAssertEqual(state.error?.code, .toolNotFound)
            XCTAssertEqual(state.error?.source, .query)
            XCTAssertEqual(state.error?.statementId, id)
            XCTAssertEqual(state.error?.toolName, OpenUIString(tool))
            XCTAssertEqual(state.error?.message, manager.queryState(for: id)?.error?.message)
        }

        synchronize(manager, [request("a", tool: "ok")])
        for _ in 0..<300 {
            if manager.queryStates(for: ["a"])["a"]?.status == .success { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let recovered = manager.queryStates(for: ["a", "b"])
        XCTAssertEqual(recovered["a"]?.status, .success)
        XCTAssertEqual(recovered["a"]?.data, .number(42))
        XCTAssertNil(recovered["a"]?.error)
        XCTAssertNil(recovered["b"])
        XCTAssertEqual(failed["a"]?.error?.code, .toolNotFound, "Previously returned states remain independent")
        manager.dispose()
        XCTAssertTrue(manager.queryStates(for: ["a", "b"]).isEmpty)
        XCTAssertNil(manager.queryState(for: "a"))
    }

    func testBatchReadsTheSnapshotErrorArrayOnce() throws {
        let core = SharedCore.shared
        try core.sync {
            // Instrument the actual manager's snapshot at its existing JSON
            // comparison boundary. The probe counts native property reads; it
            // does not replace the manager, snapshots, errors, or result data.
            let probe = try XCTUnwrap(core.context.evaluateScript("""
                (() => {
                    const original = JSON.stringify;
                    let reads = 0;
                    JSON.stringify = function(value, ...rest) {
                        const result = original.call(this, value, ...rest);
                        if (value && Object.prototype.hasOwnProperty.call(value, '__openui_errors')) {
                            const errors = value.__openui_errors;
                            Object.defineProperty(value, '__openui_errors', {
                                enumerable: true, configurable: true,
                                get() { reads++; return errors; }
                            });
                        }
                        return result;
                    };
                    return {
                        reset: () => { reads = 0; },
                        count: () => reads,
                        restore: () => { JSON.stringify = original; }
                    };
                })()
                """))
            defer { _ = probe.invokeMethod("restore", withArguments: []) }
            let manager = QueryManager(provider: nil)
            defer { manager.dispose() }
            let ids = (0..<40).map { "q\($0)" }
            synchronize(manager, ids.enumerated().map { request($0.element, defaults: .number(Double($0.offset))) })

            _ = probe.invokeMethod("reset", withArguments: [])
            let states = manager.queryStates(for: ids)
            XCTAssertEqual(states.count, ids.count)
            XCTAssertEqual(probe.invokeMethod("count", withArguments: []).toInt32(), 1)
            for (index, id) in ids.enumerated() {
                XCTAssertEqual(states[id]?.data, .number(Double(index)))
            }

            _ = probe.invokeMethod("reset", withArguments: [])
            for id in ids { XCTAssertEqual(manager.queryState(for: id)?.data, states[id]?.data) }
            XCTAssertEqual(probe.invokeMethod("count", withArguments: []).toInt32(), Int32(ids.count))

            _ = probe.invokeMethod("reset", withArguments: [])
            XCTAssertTrue(manager.queryStates(for: []).isEmpty)
            XCTAssertTrue(manager.queryStates(for: ["missing"]).isEmpty)
            XCTAssertEqual(probe.invokeMethod("count", withArguments: []).toInt32(), 0)
        }
    }
}
