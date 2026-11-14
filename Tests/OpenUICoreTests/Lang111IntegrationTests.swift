import Foundation
import OpenUICore
import OpenUILang
import SwiftUI
import XCTest

final class Lang111IntegrationTests: XCTestCase {
    private actor Provider: ToolProvider {
        struct Call: Sendable {
            let name: OpenUIString
            let arguments: OpenUIObject
        }
        private(set) var calls: [Call] = []
        func callTool(name: OpenUIString, arguments: OpenUIObject) async throws -> Value {
            calls.append(Call(name: name, arguments: arguments))
            if name == "ids" {
                try await Task.sleep(nanoseconds: 30_000_000)
                return .array([arguments["region"] ?? .null])
            }
            if name == "details", case .array(let ids) = arguments["ids"],
               case .string(let region) = ids.first {
                return .string(region)
            }
            return .object(arguments)
        }
    }

    private func library() throws -> OpenUILibrary {
        OpenUILibrary(components: try OpenUIComponentLibrary(components: [
            OpenUIComponent(name: "ProbeText", description: "Display text.",
                params: [OpenUIParameter.string("text")]) { Text($0.string("text") ?? "") }
        ], root: "ProbeText"))
    }

    @MainActor func testHostRunsQueryReadersAfterInputsAndRefetchesOnAliasedStateChange() async throws {
        let provider = Provider()
        let state = try library().makeState(toolProvider: provider)
        state.push("""
            root = ProbeText(details)
            $region = "west"
            filters = {region: $region}
            first = Query("ids", filters, [])
            args = {ids: first}
            details = Query("details", args, "pending")
            """)
        let streamingCalls = await provider.calls
        XCTAssertTrue(streamingCalls.isEmpty, "Streaming previews do not execute tools")
        state.complete()
        XCTAssertEqual(state.queryStates["details"]?.status, .loading)
        await eventually { self.text(state) == "west" }
        var calls = await provider.calls
        XCTAssertEqual(calls.map(\.name), ["ids", "details"])
        XCTAssertEqual(calls.last?.arguments["ids"], .array([.string("west")]))
        state.setState("$region", value: .string("east"))
        await eventually { self.text(state) == "east" }
        calls = await provider.calls
        XCTAssertEqual(calls.map(\.name), ["ids", "details", "ids", "details"])
        XCTAssertEqual(calls.last?.arguments["ids"], .array([.string("east")]))
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        state.reset()
    }

    @MainActor func testQueryCycleIsPreservedAsTypedParserErrorAndDoesNotFetch() async throws {
        let provider = Provider()
        let state = try library().makeState(toolProvider: provider)
        state.setSource("""
            root = ProbeText("cycle")
            a = Query("ids", {from: b}, [])
            b = Query("ids", {from: a}, [])
            """)
        XCTAssertTrue(state.errors.contains { $0.code == .queryCycle })
        try await Task.sleep(nanoseconds: 20_000_000)
        let calls = await provider.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertFalse(state.isQueryLoading)
        state.reset()
    }

    @MainActor func testMutationArgumentsResolveStatementAliasesAtActionTime() async throws {
        let provider = Provider()
        let state = try library().makeState(toolProvider: provider)
        state.setSource("""
            root = ProbeText($region)
            $region = "west"
            filters = {region: $region}
            save = Mutation("save", filters)
            """)
        state.setState("$region", value: .string("east"))
        _ = await state.perform(ActionPlan(steps: [.run(statementId: "save", refType: .mutation)]))
        let calls = await provider.calls
        XCTAssertEqual(calls.map(\.name), ["save"])
        XCTAssertEqual(calls.first?.arguments["region"], .string("east"))
        XCTAssertEqual(state.mutationStates["save"]?.status, .success)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        state.reset()
    }

    private actor SuspendedProvider: ToolProvider {
        private(set) var calls: [OpenUIString] = []
        private var waiting: CheckedContinuation<Value, Never>?
        func callTool(name: OpenUIString, arguments: OpenUIObject) async throws -> Value {
            calls.append(name)
            if name == "ids" {
                // Deliberately ignores Task cancellation until the test sends
                // a late result, as an uncooperative host transport can do.
                return await withCheckedContinuation { waiting = $0 }
            }
            return .string("stale")
        }
        func finish() {
            waiting?.resume(returning: .array([.string("old")]))
            waiting = nil
        }
    }

    @MainActor func testReplacementRetiresOldDependencyGraphDuringStreamingAndInterruption() async throws {
        for interrupted in [false, true] {
            let provider = SuspendedProvider()
            let state = try library().makeState(toolProvider: provider)
            state.setSource("""
                root = ProbeText(details)
                first = Query("ids", {}, [])
                details = Query("details", {ids: first}, "pending")
                """)
            for _ in 0..<300 {
                let calls = await provider.calls
                if calls.count == 1 { break }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            let started = await provider.calls
            XCTAssertEqual(started, ["ids"])
            state.setSource("root = ProbeText(\"replacement\")", streaming: true)
            if interrupted { state.interrupt() }
            await provider.finish()
            try await Task.sleep(nanoseconds: 20_000_000)
            let finished = await provider.calls
            XCTAssertEqual(finished, ["ids"], "Retired queries cannot launch a downstream tool")
            XCTAssertEqual(text(state), "replacement")
            XCTAssertTrue(state.queryStates.isEmpty)
            XCTAssertEqual(state.isInterrupted, interrupted)
            state.reset()
        }
    }

    @MainActor private func text(_ state: OpenUIState) -> String? {
        state.root.flatMap { PropValue.string($0, "text") }
    }

    @MainActor private func eventually(_ predicate: () -> Bool) async {
        for _ in 0..<300 {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("Lang 1.1 host did not render the settled query result")
    }
}
