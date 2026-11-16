import Combine
import XCTest
@testable import SwiftLang

final class QueryPublicationTests: XCTestCase {
    @MainActor func testADeclarationBatchDoesNotQueueOneRootPublicationPerQuery() async throws {
        let count = 40
        let started = expectation(description: "Every legitimate query enters its provider")
        started.expectedFulfillmentCount = count
        let provider = BatchProvider(onStart: { started.fulfill() })
        let schema = LibrarySchema(components: ["Box": [ParamDef(name: "value", required: true)]], callDefs: builtinCallDefs)
        let state = OpenUIState(schema: schema, toolProvider: provider)
        defer { state.reset() }
        var publications = 0
        let roots = state.$root.dropFirst().sink { _ in publications += 1 }
        defer { roots.cancel() }
        let declarations = (0..<count).map { "q\($0)=Query(\"load\",{id:\($0)},-1)" }
        let references = (0..<count).map { "q\($0)" }.joined(separator: ",")
        state.setSource((declarations + ["root=Box([\(references)])"]).joined(separator: "\n"))
        await fulfillment(of: [started], timeout: 5)
        XCTAssertEqual(state.queryStates.count, count)
        XCTAssertTrue(state.queryStates.values.allSatisfy { $0.status == .loading })
        XCTAssertLessThanOrEqual(publications, 3,
            "One synchronous root and one coalesced notification are sufficient for the loading batch")

        let finished = expectation(description: "The complete query snapshot reaches the UI")
        var fulfilled = false
        let states = state.$queryStates.sink { values in
            if !fulfilled, values.count == count, values.values.allSatisfy({ $0.status == .success }) {
                fulfilled = true
                finished.fulfill()
            }
        }
        defer { states.cancel() }
        await provider.release()
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(PropValue.value(try XCTUnwrap(state.root), "value"),
            .array((0..<count).map { .number(Double($0)) }))
        XCTAssertTrue(state.errors.isEmpty)
    }
}

private actor BatchProvider: ToolProvider {
    private let onStart: @Sendable () -> Void
    private var released = false
    private var pending: [(Value, CheckedContinuation<Value, Never>)] = []
    init(onStart: @escaping @Sendable () -> Void) { self.onStart = onStart }
    func callTool(name: OpenUIString, arguments: OpenUIObject) async throws -> Value {
        let value = arguments.last(where: { $0.key == "id" })?.value ?? .null
        onStart()
        if released { return value }
        return await withCheckedContinuation { pending.append((value, $0)) }
    }
    func release() {
        released = true
        let current = pending
        pending.removeAll()
        current.forEach { $0.1.resume(returning: $0.0) }
    }
}
