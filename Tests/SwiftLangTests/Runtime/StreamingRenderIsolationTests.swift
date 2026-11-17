#if os(macOS)
import AppKit
import Combine
import SwiftUI
import XCTest
@testable import SwiftLang

final class StreamingRenderIsolationTests: XCTestCase {
    @MainActor private func library(_ log: RenderLog, capture: String = "original") throws -> OpenUIComponentLibrary {
        try OpenUIComponentLibrary(components: [
            OpenUIComponent(name: "Group", description: "Children", params: [ParamDef(name: "children", required: true)]) { context in
                VStack {
                    ForEach(context.children()) { child in context.render(child.value) }
                }
            },
            OpenUIComponent(name: "Probe", description: "Observed leaf", params: [
                OpenUIParameter.string("id"), OpenUIParameter.string("text")
            ]) { context in CountingComponent(context: context, log: log, capture: capture) }
        ])
    }

    @MainActor func testStreamingTailLeavesMountedSiblingBuilderAndBodyAlone() throws {
        let log = RenderLog(), library = try self.library(log)
        let state = OpenUIState(schema: library.library.toSchema())
        defer { state.reset() }
        state.push("root=Group([fixed,tail])\nfixed=Probe(\"fixed\",\"stable\")\ntail=Probe(\"tail\",\"")
        let harness = RenderHarness(AnyView(SwiftLangView(state: state, registry: library.registry)))
        defer { harness.close() }
        harness.settle()
        let fixedBuilders = log.builders["fixed", default: 0]
        let fixedBodies = log.bodies["fixed", default: 0]
        let fixedMounts = log.mounts["fixed", default: 0]
        XCTAssertGreaterThan(fixedBuilders, 0)
        XCTAssertGreaterThan(fixedBodies, 0)
        var text = ""
        // The pinned parser trims an unfinished source's trailing whitespace;
        // its raw buffer retains that space once the next token arrives.
        let previews = ["SHANGHAI", "SHANGHAI →", "SHANGHAI → SUZHOU",
            "SHANGHAI → SUZHOU · 2 DAYS", "SHANGHAI → SUZHOU · 2 DAYS · 3 位成人"]
        for (index, chunk) in ["SHANGHAI", " → ", "SUZHOU", " · 2 DAYS", " · 3 位成人"].enumerated() {
            text += chunk
            state.push(chunk)
            harness.settle()
            XCTAssertEqual(log.shown["tail"]?.text, previews[index], "The mounted view must advance before complete")
            XCTAssertEqual(log.builders["fixed"], fixedBuilders)
            XCTAssertEqual(log.bodies["fixed"], fixedBodies)
        }
        XCTAssertFalse(try XCTUnwrap(log.shown["tail"]).ready)
        state.push("\")")
        harness.settle()
        XCTAssertTrue(try XCTUnwrap(log.shown["tail"]).ready, "Delimiter-only readiness must reach the same mounted leaf")
        XCTAssertEqual(log.shown["tail"]?.text, text)
        XCTAssertEqual(log.mounts["fixed"], fixedMounts)
        state.complete()
        harness.settle()
        XCTAssertFalse(try XCTUnwrap(log.shown["fixed"]).streaming)
        XCTAssertEqual(log.mounts["fixed"], fixedMounts)
        state.setSource("root=Group([fixed])\nfixed=Probe(\"fixed\",\"replacement\")")
        harness.settle()
        XCTAssertEqual(log.shown["fixed"]?.text, "replacement")
        XCTAssertGreaterThan(log.mounts["fixed", default: 0], fixedMounts)
    }

    @MainActor func testClosingAStringRestoresItsTrailingWhitespaceInTheSameMountedLeaf() throws {
        let log = RenderLog(), library = try self.library(log)
        let state = OpenUIState(schema: library.library.toSchema())
        defer { state.reset() }
        state.push("root=Probe(\"tail\",\"SHANGHAI → ")
        let harness = RenderHarness(AnyView(SwiftLangView(state: state, registry: library.registry)))
        defer { harness.close() }
        harness.settle()
        XCTAssertEqual(log.shown["tail"]?.text, "SHANGHAI →")
        let mounts = log.mounts["tail", default: 0]
        XCTAssertGreaterThan(mounts, 0)
        state.push("\")")
        harness.settle()
        XCTAssertEqual(log.shown["tail"]?.text, "SHANGHAI → ",
            "A closed string retains its authored trailing space; display code must not trim it")
        XCTAssertTrue(try XCTUnwrap(log.shown["tail"]).ready)
        XCTAssertFalse(state.isComplete)
        XCTAssertEqual(log.mounts["tail", default: 0], mounts)
    }

    @MainActor func testFieldsBindingsAndDefaultsNotifyWithoutChangedComponentProps() throws {
        let log = RenderLog(), library = try self.library(log)
        let state = OpenUIState(schema: library.library.toSchema())
        defer { state.reset() }
        state.push("root=Group([field])\nfield=Probe(\"field\",\"stable\")\n")
        let harness = RenderHarness(AnyView(SwiftLangView(state: state, registry: library.registry)))
        defer { harness.close() }
        harness.settle()
        let mounted = log.mounts["field", default: 0]
        state.setFieldValue(form: nil, name: "shared", value: .string("edited"))
        harness.settle()
        XCTAssertEqual(log.shown["field"]?.field, "edited")
        XCTAssertEqual(log.shown["field"]?.binding, "edited")
        state.push("$late=\"arrived during streaming\"\n")
        harness.settle()
        XCTAssertEqual(log.shown["field"]?.lateDefault, "arrived during streaming")
        XCTAssertEqual(log.mounts["field"], mounted)
    }

    @MainActor func testUndispatchedQueryAndMutationDoNotWakeStableSiblingForEachTextChunk() throws {
        let log = RenderLog(), library = try self.library(log)
        let state = OpenUIState(schema: library.library.toSchema())
        defer { state.reset() }
        state.push("q=Query(\"load\",{},\"default\")\nsave=Mutation(\"save\",{})\nroot=Group([fixed,tail])\nfixed=Probe(\"fixed\",\"stable\")\ntail=Probe(\"tail\",\"")
        let harness = RenderHarness(AnyView(SwiftLangView(state: state, registry: library.registry)))
        defer { harness.close() }
        harness.settle()
        let builders = log.builders["fixed", default: 0], bodies = log.bodies["fixed", default: 0]
        XCTAssertGreaterThan(builders, 0)
        XCTAssertTrue(try XCTUnwrap(log.shown["fixed"]).loading)
        for chunk in ["one", " two", " three"] {
            state.push(chunk)
            harness.settle()
            XCTAssertEqual(log.builders["fixed"], builders)
            XCTAssertEqual(log.bodies["fixed"], bodies)
        }
        XCTAssertEqual(log.shown["tail"]?.text, "one two three")
    }

    @MainActor func testDirectEnvironmentObjectEntryReceivesReadinessAndCompletion() throws {
        let log = RenderLog(), library = try self.library(log)
        let state = OpenUIState(schema: library.library.toSchema())
        defer { state.reset() }
        state.push("root=Probe(\"direct\",\"ready")
        let node = try XCTUnwrap(state.root)
        let harness = RenderHarness(AnyView(RenderNode(element: node, registry: library.registry).environmentObject(state)))
        defer { harness.close() }
        harness.settle()
        XCTAssertFalse(try XCTUnwrap(log.shown["direct"]).ready)
        state.push("\")")
        harness.settle()
        XCTAssertTrue(try XCTUnwrap(log.shown["direct"]).ready)
        state.complete()
        harness.settle()
        XCTAssertFalse(try XCTUnwrap(log.shown["direct"]).streaming)
        state.setFieldValue(form: nil, name: "shared", value: .string("direct edit"))
        harness.settle()
        XCTAssertEqual(log.shown["direct"]?.field, "direct edit")
    }

    @MainActor func testDirectOldSnapshotBecomesNoninteractiveWhenRemovedInTheSameStream() throws {
        let log = RenderLog(), library = try self.library(log)
        let state = OpenUIState(schema: library.library.toSchema())
        defer { state.reset() }
        state.push("root=Probe(\"direct\",\"original\")\n")
        let node = try XCTUnwrap(state.root)
        let harness = RenderHarness(AnyView(RenderNode(element: node, registry: library.registry).environmentObject(state)))
        defer { harness.close() }
        harness.settle()
        XCTAssertTrue(try XCTUnwrap(log.shown["direct"]).ready)
        let revision = state.sourceRevision
        state.push("root=Probe(\"other\",\"replacement\")\n")
        harness.settle()
        XCTAssertEqual(state.sourceRevision, revision)
        XCTAssertFalse(try XCTUnwrap(log.shown["direct"]).ready)
    }

    @MainActor func testParentEnvironmentAndChangedRegistryClosureStillReachStableLeaf() throws {
        let log = RenderLog(), first = try library(log)
        let state = OpenUIState(schema: first.library.toSchema())
        defer { state.reset() }
        state.setSource("root=Group([leaf])\nleaf=Probe(\"leaf\",\"stable\")")
        var values = OpenUIContextValues()
        values[ProbeEnvironmentKey.self] = "first environment"
        let harness = RenderHarness(AnyView(SwiftLangView(state: state, registry: first.registry)
            .openUIContextValues(values).openUIResources(["hint": .string("first resource")]).openUIForm("first form")))
        defer { harness.close() }
        harness.settle()
        XCTAssertEqual(log.shown["leaf"]?.environment, "first environment")
        values[ProbeEnvironmentKey.self] = "second environment"
        harness.host.rootView = AnyView(SwiftLangView(state: state, registry: first.registry)
            .openUIContextValues(values).openUIResources(["hint": .string("second resource")]).openUIForm("second form"))
        harness.settle()
        XCTAssertEqual(log.shown["leaf"]?.environment, "second environment")
        XCTAssertEqual(log.shown["leaf"]?.resource, "second resource")
        XCTAssertEqual(log.shown["leaf"]?.form, "second form")
        let second = try library(log, capture: "changed closure")
        harness.host.rootView = AnyView(SwiftLangView(state: state, registry: second.registry))
        harness.settle()
        XCTAssertEqual(log.shown["leaf"]?.capture, "changed closure")
    }

    @MainActor func testQueryLifecycleUpdatesContextWhenLeafPropsStayConstant() async throws {
        let log = RenderLog(), library = try self.library(log)
        let started = expectation(description: "Query entered provider")
        let provider = RenderProvider { started.fulfill() }
        defer { Task { await provider.finish() } }
        let state = OpenUIState(schema: library.library.toSchema(), toolProvider: provider)
        defer { state.reset() }
        state.setSource("q=Query(\"load\",{},\"pending\")\nroot=Group([leaf])\nleaf=Probe(\"query\",\"fixed\")")
        await fulfillment(of: [started], timeout: 3)
        let harness = RenderHarness(AnyView(SwiftLangView(state: state, registry: library.registry)))
        defer { harness.close() }
        harness.settle()
        XCTAssertTrue(try XCTUnwrap(log.shown["query"]).loading)
        let finished = expectation(description: "Query result published")
        var fulfilled = false
        let subscription = state.$queryStates.sink { queries in
            if !fulfilled, queries["q"]?.status == .success { fulfilled = true; finished.fulfill() }
        }
        defer { subscription.cancel() }
        await provider.finish()
        await fulfillment(of: [finished], timeout: 3)
        harness.settle()
        XCTAssertEqual(log.shown["query"]?.text, "fixed")
        XCTAssertFalse(try XCTUnwrap(log.shown["query"]).loading)
    }

    @MainActor func testDirectComponentHostPreservesChangedParentClosureCapture() throws {
        let log = RenderLog(), library = try self.library(log)
        let state = OpenUIState(schema: library.library.toSchema())
        defer { state.reset() }
        state.setSource("root=Probe(\"direct\",\"same value\")")
        let element = try XCTUnwrap(state.root)
        let harness = RenderHarness(AnyView(OpenUIComponentHost(element: element, registry: library.registry) { context in
            CountingComponent(context: context, log: log, capture: "first capture")
        }.environmentObject(state)))
        defer { harness.close() }
        harness.settle()
        XCTAssertEqual(log.shown["direct"]?.capture, "first capture")
        harness.host.rootView = AnyView(OpenUIComponentHost(element: element, registry: library.registry) { context in
            CountingComponent(context: context, log: log, capture: "second capture")
        }.environmentObject(state))
        harness.settle()
        XCTAssertEqual(log.shown["direct"]?.capture, "second capture")
    }

    @MainActor func testNestedEnvironmentObjectUsesTheNearestDocumentForReadsAndWrites() throws {
        let log = RenderLog(), innerLibrary = try library(log)
        let inner = OpenUIState(schema: innerLibrary.library.toSchema())
        inner.setSource("root=Probe(\"nested\",\"inner\")")
        inner.setFieldValue(form: nil, name: "shared", value: .string("inner field"))
        let node = try XCTUnwrap(inner.root)
        let outerLibrary = try OpenUIComponentLibrary(components: [
            OpenUIComponent(name: "Outer", description: "Nested document", params: []) { _ in
                RenderNode(element: node, registry: innerLibrary.registry).environmentObject(inner)
            }
        ])
        let outer = OpenUIState(schema: outerLibrary.library.toSchema())
        defer { log.writeNested = nil; inner.reset(); outer.reset() }
        outer.setSource("root=Outer()")
        outer.setFieldValue(form: nil, name: "shared", value: .string("outer field"))
        let harness = RenderHarness(AnyView(SwiftLangView(state: outer, registry: outerLibrary.registry)))
        defer { harness.close() }
        harness.settle()
        XCTAssertEqual(log.shown["nested"]?.field, "inner field")
        XCTAssertTrue(try XCTUnwrap(log.shown["nested"]).ready)
        try XCTUnwrap(log.writeNested)(.string("only inner changed"))
        harness.settle()
        XCTAssertEqual(inner.fieldValue(form: nil, name: "shared"), .string("only inner changed"))
        XCTAssertEqual(outer.fieldValue(form: nil, name: "shared"), .string("outer field"))
        XCTAssertEqual(log.shown["nested"]?.field, "only inner changed")
    }

    @MainActor func testRawRegistryRenderingStillRequiresNoRuntimeEnvironment() {
        let log = RenderLog()
        let registry: OpenUIComponentRegistry = ["Bare": { element, _ in
            log.raw += 1
            return AnyView(Text(PropValue.string(element, "text") ?? ""))
        }]
        let harness = RenderHarness(AnyView(RenderNode(element:
            EvaluatedElement(typeName: "Bare", props: [("text", .string("no State required"))]), registry: registry)))
        defer { harness.close() }
        harness.settle()
        XCTAssertGreaterThan(log.raw, 0)
    }

    @MainActor func testMountedStoreReadersLeaveUnrelatedSiblingBuildersAndBodiesAlone() throws {
        let log = SelectiveFieldLog()
        let library = try OpenUIComponentLibrary(components: [
            OpenUIComponent(name: "Group", description: "Children", params: [ParamDef(name: "children", required: true)]) { context in
                VStack { ForEach(context.children()) { context.render($0.value) } }
            },
            OpenUIComponent(name: "Reader", description: "One field reader", params: [
                OpenUIParameter.string("id"), OpenUIParameter.string("field")
            ]) { SelectiveFieldComponent(context: $0, log: log) }
        ])
        let state = OpenUIState(schema: library.library.toSchema())
        defer { state.reset() }
        state.setSource("root=Group([left,right,plain])\nleft=Reader(\"left\",\"left field\")\nright=Reader(\"right\",\"right field\")\nplain=Reader(\"plain\",\"\")")
        state.setFieldValue(form: nil, name: "left field", value: .string("left before"))
        state.setFieldValue(form: nil, name: "right field", value: .string("right before"))
        let harness = RenderHarness(AnyView(SwiftLangView(state: state, registry: library.registry)))
        defer { harness.close() }
        harness.settle()
        let builders = log.builders, bodies = log.bodies
        XCTAssertEqual(log.values["left"], "left before")
        XCTAssertEqual(log.values["right"], "right before")
        XCTAssertGreaterThan(builders["plain", default: 0], 0)
        state.setFieldValue(form: nil, name: "left field", value: .string("left after"))
        harness.settle()
        XCTAssertEqual(log.values["left"], "left after")
        XCTAssertGreaterThan(log.builders["left", default: 0], builders["left", default: 0])
        XCTAssertGreaterThan(log.bodies["left", default: 0], bodies["left", default: 0])
        for id in ["right", "plain"] {
            XCTAssertEqual(log.builders[id], builders[id])
            XCTAssertEqual(log.bodies[id], bodies[id])
        }
        let afterBuilders = log.builders, afterBodies = log.bodies
        state.setFieldValue(form: nil, name: "unobserved", value: .string("no component reads this"))
        harness.settle()
        XCTAssertEqual(log.builders, afterBuilders)
        XCTAssertEqual(log.bodies, afterBodies)
    }

    @MainActor func testReplacingNearestEnvironmentObjectRebindsTheMountedSubscription() throws {
        let log = RenderLog(), library = try self.library(log)
        let first = OpenUIState(schema: library.library.toSchema()), second = OpenUIState(schema: library.library.toSchema())
        defer { first.reset(); second.reset() }
        for state in [first, second] { state.setSource("root=Probe(\"direct\",\"same source\")") }
        first.setFieldValue(form: nil, name: "shared", value: .string("first document"))
        second.setFieldValue(form: nil, name: "shared", value: .string("second document"))
        let node = try XCTUnwrap(first.root)
        let harness = RenderHarness(AnyView(RenderNode(element: node, registry: library.registry).environmentObject(first)))
        defer { harness.close() }
        harness.settle()
        XCTAssertEqual(log.shown["direct"]?.field, "first document")
        harness.host.rootView = AnyView(RenderNode(element: node, registry: library.registry).environmentObject(second))
        harness.settle()
        XCTAssertEqual(log.shown["direct"]?.field, "second document")
        let bodies = log.bodies["direct"]
        first.setFieldValue(form: nil, name: "shared", value: .string("retired owner"))
        harness.settle()
        XCTAssertEqual(log.shown["direct"]?.field, "second document")
        XCTAssertEqual(log.bodies["direct"], bodies)
        second.setFieldValue(form: nil, name: "shared", value: .string("current owner"))
        harness.settle()
        XCTAssertEqual(log.shown["direct"]?.field, "current owner")
    }
}

@MainActor private final class SelectiveFieldLog {
    var builders: [String: Int] = [:]
    var bodies: [String: Int] = [:]
    var values: [String: String] = [:]
}

@MainActor private struct SelectiveFieldComponent: View {
    let context: OpenUIComponentContext
    let log: SelectiveFieldLog

    init(context: OpenUIComponentContext, log: SelectiveFieldLog) {
        self.context = context; self.log = log
        log.builders[context.string("id") ?? "unknown", default: 0] += 1
    }

    var body: some View {
        let id = context.string("id") ?? "unknown", field = context.string("field") ?? ""
        let value = field.isEmpty ? Value.string("static") : context.fieldBinding(field).wrappedValue
        let text = displayString(value)
        let _ = record(id: id, text: text)
        Text(text)
    }

    private func displayString(_ value: Value) -> String {
        if case .string(let string) = value { return string.displayString }
        return ""
    }

    private func record(id: String, text: String) {
        log.bodies[id, default: 0] += 1
        log.values[id] = text
    }
}

private enum ProbeEnvironmentKey: OpenUIContextKey { static let defaultValue = "default environment" }

@MainActor private final class RenderLog {
    struct Snapshot {
        let text: String, field: String, binding: String, lateDefault: String
        let ready: Bool, streaming: Bool, loading: Bool
        let environment: String, resource: String, form: String?, capture: String
    }
    var builders: [String: Int] = [:]
    var bodies: [String: Int] = [:]
    var mounts: [String: Int] = [:]
    var shown: [String: Snapshot] = [:]
    var raw = 0
    var writeNested: ((Value) -> Void)?

    func record(_ context: OpenUIComponentContext, capture: String) -> String {
        let id = context.string("id") ?? "unknown"
        func text(_ value: Value?) -> String {
            if let value, case .string(let string) = value { return string.displayString }
            return ""
        }
        bodies[id, default: 0] += 1
        shown[id] = Snapshot(text: context.string("text") ?? "",
            field: text(context.fieldValue("shared")), binding: text(context.fieldBinding("shared").wrappedValue),
            lateDefault: text(context.fieldValue("$late")), ready: context.canInteract, streaming: context.isStreaming,
            loading: context.isQueryLoading,
            environment: context.values[ProbeEnvironmentKey.self], resource: text(context.resource("hint")),
            form: context.formName, capture: capture)
        return context.string("text") ?? ""
    }
}

@MainActor private struct CountingComponent: View {
    let context: OpenUIComponentContext
    let log: RenderLog
    let capture: String

    init(context: OpenUIComponentContext, log: RenderLog, capture: String) {
        self.context = context; self.log = log; self.capture = capture
        log.builders[context.string("id") ?? "unknown", default: 0] += 1
        if context.string("id") == "nested" {
            log.writeNested = context.weakOperation { context, value in
                context.fieldBinding("shared").wrappedValue = value
            }
        }
    }

    var body: some View {
        Text(log.record(context, capture: capture))
            .background(RenderMountMarker(log: log, id: context.string("id") ?? "unknown"))
    }
}

private struct RenderMountMarker: NSViewRepresentable {
    let log: RenderLog
    let id: String
    func makeNSView(context: Context) -> NSView {
        log.mounts[id, default: 0] += 1
        return NSView()
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

@MainActor private final class RenderHarness {
    let host: NSHostingView<AnyView>
    private let window: NSWindow
    init(_ content: AnyView) {
        _ = NSApplication.shared
        host = NSHostingView(rootView: content)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 500),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFront(nil)
    }
    func settle() {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        host.layoutSubtreeIfNeeded()
    }
    func close() { window.close() }
}

private actor RenderProvider: ToolProvider {
    private let started: @Sendable () -> Void
    private var pending: CheckedContinuation<Value, Never>?
    private var released = false
    init(started: @escaping @Sendable () -> Void) { self.started = started }
    func callTool(name: OpenUIString, arguments: OpenUIObject) async throws -> Value {
        started()
        if released { return .string("ready") }
        return await withCheckedContinuation { pending = $0 }
    }
    func finish() {
        released = true
        pending?.resume(returning: .string("ready"))
        pending = nil
    }
}
#endif
