import Combine
import SwiftUI
import XCTest
@testable import SwiftLang

final class ComponentTargetLifecycleTests: XCTestCase {
    private func schema() -> LibrarySchema {
        LibrarySchema(components: [
            "Stack": [ParamDef(name: "children", required: true)],
            "Input": [ParamDef(name: "value", required: true, isBindable: true)],
            "Box": [ParamDef(name: "value", required: true)],
            "Button": [ParamDef(name: "label", required: true), ParamDef(name: "action", required: true)]
        ], callDefs: builtinCallDefs)
    }

    private let source = """
    $shown=true
    $text="initial"
    $count=0
    $trigger=0
    root=Stack($shown ? [Input($text),Input($count=$value+2),Box("field"),Button("Send",@ToAssistant("removed"))] : [])
    """

    @MainActor private func contexts(_ state: OpenUIState) throws -> [OpenUIComponentContext] {
        let children = PropValue.children(try XCTUnwrap(state.root))
        XCTAssertEqual(children.count, 4)
        return children.map { OpenUIComponentContext(element: $0, registry: [:], state: state) }
    }

    @MainActor func testConditionalRemovalRetiresOldActionsAndComponentWrites() async throws {
        let state = OpenUIState(schema: schema())
        state.setSource(source)
        let contexts = try contexts(state)
        guard contexts.count == 4 else { return }
        let direct = try XCTUnwrap(contexts[0].binding("value"))
        let reactive = try XCTUnwrap(contexts[1].binding("value"))
        let field = contexts[2].fieldBinding("$field", fallback: .string("initial"))
        let action = try XCTUnwrap(contexts[3].action())
        var delivered: [ActionEvent] = []
        state.onAction = { delivered.append($0) }
        XCTAssertTrue(contexts.allSatisfy(\.canInteract))
        direct.wrappedValue = .string("accepted")
        reactive.wrappedValue = .number(3)
        field.wrappedValue = .string("accepted")
        XCTAssertEqual(state.stateValue("$text"), .string("accepted"))
        XCTAssertEqual(state.stateValue("$count"), .number(5))
        let revision = state.sourceRevision

        state.setState("$shown", value: .boolean(false))

        XCTAssertEqual(state.sourceRevision, revision, "This is a branch removal, not a replacement document")
        XCTAssertTrue(PropValue.children(try XCTUnwrap(state.root)).isEmpty)
        XCTAssertTrue(contexts.allSatisfy { !$0.canInteract })
        direct.wrappedValue = .string("obsolete")
        reactive.wrappedValue = .number(20)
        field.wrappedValue = .string("obsolete")
        contexts[2].initializeField("$late", value: .string("obsolete"))
        let planEvents = await contexts[3].perform(action)
        let legacyEvents = await contexts[3].triggerAction("obsolete")
        XCTAssertTrue(planEvents.isEmpty)
        XCTAssertTrue(legacyEvents.isEmpty)
        XCTAssertTrue(delivered.isEmpty)
        XCTAssertEqual(state.stateValue("$text"), .string("accepted"))
        XCTAssertEqual(state.stateValue("$count"), .number(5))
        XCTAssertEqual(state.fieldValue(form: nil, name: "$field"), .string("accepted"))
        XCTAssertNil(state.snapshotState()["$late"])
    }

    @MainActor func testQueuedWritesRecheckTheTargetAfterAnEarlierQueuedRemoval() throws {
        let state = OpenUIState(schema: schema())
        state.setSource(source)
        let contexts = try contexts(state)
        guard contexts.count == 4 else { return }
        let direct = try XCTUnwrap(contexts[0].binding("value"))
        let reactive = try XCTUnwrap(contexts[1].binding("value"))
        let field = contexts[2].fieldBinding("$field")
        var queued = false
        let subscription = state.$root.dropFirst().sink { _ in
            guard !queued, state.stateValue("$trigger") == .number(1) else { return }
            queued = true
            state.setState("$shown", value: .boolean(false))
            XCTAssertTrue(contexts.allSatisfy(\.canInteract), "The removal is still queued when these callbacks arrive")
            direct.wrappedValue = .string("obsolete")
            reactive.wrappedValue = .number(20)
            field.wrappedValue = .string("obsolete")
            contexts[2].initializeField("$late", value: .string("obsolete"))
        }
        defer { subscription.cancel() }

        state.setState("$trigger", value: .number(1))

        XCTAssertTrue(queued)
        XCTAssertTrue(PropValue.children(try XCTUnwrap(state.root)).isEmpty)
        XCTAssertEqual(state.stateValue("$text"), .string("initial"))
        XCTAssertEqual(state.stateValue("$count"), .number(0))
        XCTAssertNil(state.snapshotState()["$field"])
        XCTAssertNil(state.snapshotState()["$late"])
    }

    @MainActor func testWeakEditingCallbacksAndPresentationWritesRetireWithTheirTarget() throws {
        let state = OpenUIState(schema: schema())
        state.setSource(source)
        let contexts = try contexts(state)
        guard contexts.count == 4 else { return }
        let presentation = try XCTUnwrap(contexts[0].presentationBinding("value"))
        let edit: (Value) -> Void = contexts[2].weakOperation { context, value in
            context.fieldBinding("$field").wrappedValue = value
        }
        state.setState("$shown", value: .boolean(false))

        presentation.wrappedValue = .string("obsolete")
        contexts[2].setPresentationFieldValue("$presentation", value: .string("obsolete"))
        edit(.string("obsolete"))

        XCTAssertEqual(state.stateValue("$text"), .string("initial"))
        XCTAssertNil(state.snapshotState()["$presentation"])
        XCTAssertNil(state.snapshotState()["$field"])
    }

    @MainActor func testPartialPresentationControlAndCompletedSnapshotRemainUsable() throws {
        let state = OpenUIState(schema: schema())
        state.push("$open=true\nroot=Input($open")
        let pending = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: [:], state: state)
        XCTAssertFalse(pending.canInteract)
        XCTAssertTrue(state.isElementCurrent(pending.element))
        let close = try XCTUnwrap(pending.presentationBinding("value"))
        close.wrappedValue = .boolean(false)
        pending.setPresentationFieldValue("$presentation", value: .boolean(false))
        XCTAssertEqual(state.stateValue("$open"), .boolean(false))
        XCTAssertEqual(state.fieldValue(form: nil, name: "$presentation"), .boolean(false))

        state.push(")")
        state.complete()

        XCTAssertTrue(pending.canInteract, "An unchanged older snapshot must resolve the current readiness")
        try XCTUnwrap(pending.binding("value")).wrappedValue = .boolean(true)
        XCTAssertEqual(state.stateValue("$open"), .boolean(true))
    }

    @MainActor func testHostWritesRemainIndependentOfRemovedControls() throws {
        let state = OpenUIState(schema: schema())
        state.setSource(source)
        let input = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first)
        let elementBinding = try XCTUnwrap(state.binding(for: input, prop: "value"))
        state.setState("$shown", value: .boolean(false))

        elementBinding.wrappedValue = .string("host element binding")
        XCTAssertEqual(state.stateValue("$text"), .string("host element binding"))
        state.binding(for: "$text").wrappedValue = .string("host named binding")
        state.setFieldValue(form: nil, name: "$field", value: .string("host field"))
        state.initializeField(form: nil, name: "$late", value: .string("host initial value"))

        XCTAssertEqual(state.stateValue("$text"), .string("host named binding"))
        XCTAssertEqual(state.fieldValue(form: nil, name: "$field"), .string("host field"))
        XCTAssertEqual(state.fieldValue(form: nil, name: "$late"), .string("host initial value"))
    }

    @MainActor func testAnAlreadyStartedActionCanRemoveItsOwnControlAndContinue() async throws {
        let state = OpenUIState(schema: schema())
        state.setSource("$shown=true\nroot=Stack($shown ? [Button(\"Hide\",Action([@Set($shown,false),@ToAssistant(\"after hide\")]))] : [])")
        let button = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first)
        let context = OpenUIComponentContext(element: button, registry: [:], state: state)
        let plan = try XCTUnwrap(context.action())
        var delivered: [ActionEvent] = []
        state.onAction = { delivered.append($0) }

        let events = await context.perform(plan)

        XCTAssertTrue(PropValue.children(try XCTUnwrap(state.root)).isEmpty)
        XCTAssertEqual(events.count, 1, "Target retirement rejects a later activation, not subsequent steps of this action")
        XCTAssertEqual(delivered.count, 1)
        XCTAssertFalse(context.canInteract)
    }

    @MainActor func testNativeFunctionControlsBelongToTheCurrentDocument() throws {
        let native = EvaluatedElement(typeName: "Input", props: [("value", .binding("$text"))])
        let base = schema()
        let schema = LibrarySchema(components: base.components,
            callDefs: base.callDefs.merging(["Native": CallDef(kind: .function, params: [])]) { _, new in new })
        let state = OpenUIState(schema: schema, functions: [
            "Native": CustomFunction(params: [], fn: { _ in .element(native) })
        ])
        state.setSource("$text=\"initial\"\nroot=Stack([@Native()])")
        let current = try XCTUnwrap(PropValue.children(try XCTUnwrap(state.root)).first)
        let context = OpenUIComponentContext(element: current, registry: [:], state: state)
        XCTAssertTrue(context.canInteract)
        try XCTUnwrap(context.binding("value")).wrappedValue = .string("accepted")
        XCTAssertEqual(state.stateValue("$text"), .string("accepted"))
    }
}
