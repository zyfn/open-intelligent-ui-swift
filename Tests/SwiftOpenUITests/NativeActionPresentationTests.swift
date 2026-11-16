import SwiftLang
import XCTest
@testable import SwiftOpenUI

final class NativeActionPresentationTests: XCTestCase {
    private let conversation = ActionStep.continueConversation(messageAST: .str("完整消息"), contextAST: nil)

    private func classify(_ steps: [ActionStep], complete: Bool = true) -> NativeActionPresentation {
        .classify(.actionPlan(ActionPlan(steps: steps, isSourceComplete: complete)), ready: true)
    }

    func testConversationClassificationUsesStepsAndPreservesMixedIntent() {
        XCTAssertEqual(classify([conversation]), .init(continuesConversation: true, submitsForm: true))
        XCTAssertEqual(classify([.set(target: "$x", valueAST: .num(1)), conversation, .reset(targets: ["$x"])]),
                       .init(continuesConversation: true, submitsForm: true))
        for other in [ActionStep.run(statementId: "q", refType: .query),
                      .run(statementId: "save", refType: .mutation),
                      .custom(name: "Save", args: []), .openUrl(urlAST: .str("https://example.invalid"))] {
            XCTAssertEqual(classify([other, conversation]), .init(submitsForm: true))
            XCTAssertEqual(classify([conversation, other]), .init(submitsForm: true))
        }
        XCTAssertEqual(classify([conversation, conversation]), .init(submitsForm: true),
                       "Multiple outbound messages are not a single conversational intent")
        XCTAssertEqual(classify([conversation], complete: false), .init())
        XCTAssertEqual(classify([]), .init())
    }

    func testSubmissionWidthClassificationIsIndependentOfConversationArrow() {
        XCTAssertEqual(classify([.run(statementId: "save", refType: .mutation)]), .init(submitsForm: true))
        XCTAssertEqual(classify([.custom(name: "Save", args: [])]), .init(submitsForm: true))
        XCTAssertEqual(classify([.run(statementId: "load", refType: .query)]), .init())
        XCTAssertEqual(classify([.openUrl(urlAST: .str("https://example.invalid"))]), .init())
        XCTAssertEqual(classify([.set(target: "$x", valueAST: .num(2)), .reset(targets: ["$x"])]), .init())
    }

    func testDefaultAndLegacyDispatchShapesWaitForReadiness() {
        let actions: [Value?] = [nil, .null, .object([.init(key: "type", value: .string("continue_conversation"))])]
        for action in actions {
            XCTAssertEqual(NativeActionPresentation.classify(action, ready: false), .init())
            XCTAssertEqual(NativeActionPresentation.classify(action, ready: true),
                           .init(continuesConversation: true, submitsForm: true))
        }
        XCTAssertEqual(NativeActionPresentation.classify(.object([.init(key: "type", value: .string("open_url"))]), ready: true), .init())
        XCTAssertEqual(NativeActionPresentation.classify(.object([.init(key: "type", value: .string("save_record"))]), ready: true), .init(submitsForm: true))
        XCTAssertEqual(NativeActionPresentation.classify(.string("continue_conversation"), ready: true), .init(),
                       "An unsupported string action cannot become a semantic icon")
        XCTAssertEqual(NativeActionPresentation.classify(.undefined, ready: true), .init())
        let object: Value = .object([
            .init(key: "type", value: .string("open_url")),
            .init(key: "steps", value: .array([.actionPlan(ActionPlan(steps: [conversation]))]))
        ])
        XCTAssertFalse(NativeActionPresentation.classify(object, ready: true).continuesConversation,
                       "Ordinary object data must not be recognized as ActionPlan steps")
    }

    func testSingleSubmissionRejectsUnresolvedCollectionPositions() {
        let button = EvaluatedElement(typeName: "Button", props: [("label", .string("Send"))])
        func group(_ source: NativeSourceReadiness) -> EvaluatedElement {
            EvaluatedElement(typeName: "Buttons", props: [("buttons", .array([.element(button)]))],
                sourceReadiness: .init(complete: false, closed: true, children: [
                    "direction": .init(complete: true, closed: true), "buttons": source
                ]))
        }
        XCTAssertFalse(NativeActionPresentation.fillsSingleFormSubmission(group(.init(complete: false, closed: false))))
        XCTAssertFalse(NativeActionPresentation.fillsSingleFormSubmission(group(.init(complete: false, closed: true,
            expectedCount: 2, valueIndices: [0, nil]))))
        XCTAssertFalse(NativeActionPresentation.fillsSingleFormSubmission(group(.init(complete: false, closed: true,
            expectedCount: 1, pendingChildren: [0: .init(complete: false, closed: true)]))))
        XCTAssertTrue(NativeActionPresentation.fillsSingleFormSubmission(group(.init(complete: true, closed: true,
            expectedCount: 1, valueIndices: [0]))))
    }

    @MainActor func testStreamingDefaultActionDoesNotAppearBeforeItsFinalAction() throws {
        let library = try OpenUIComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        state.push("root=Button(\"继续\"")
        XCTAssertFalse(NativeActionPresentation.button(try XCTUnwrap(state.root)).continuesConversation)
        state.push(",@OpenUrl(\"https://example.invalid\"))\nunrelated=TextContent(\"still arriving")
        XCTAssertFalse(state.isComplete)
        XCTAssertFalse(NativeActionPresentation.button(try XCTUnwrap(state.root)).continuesConversation,
                       "The label does not override the final navigation action")
    }

    @MainActor func testSingleSubmissionWaitsForItsOwnStructureAndDependenciesOnly() throws {
        let library = try OpenUIComponents.library()
        let growing = OpenUIState(schema: library.library.toSchema())
        growing.push("root=Buttons([Button(\"Send\",@ToAssistant(\"send\"))")
        XCTAssertFalse(NativeActionPresentation.fillsSingleFormSubmission(try XCTUnwrap(growing.root)))
        growing.push(",Button(\"Other\",@ToAssistant(\"other\"))],\"row\")")
        growing.complete()
        XCTAssertFalse(NativeActionPresentation.fillsSingleFormSubmission(try XCTUnwrap(growing.root)))

        let single = OpenUIState(schema: library.library.toSchema())
        single.push("root=Buttons([Button(\"Send\",@ToAssistant(message))],\"row\")\nmessage=\"unfinished")
        XCTAssertFalse(NativeActionPresentation.fillsSingleFormSubmission(try XCTUnwrap(single.root)))
        single.push(" message\"\nunrelated=TextContent(\"still arriving")
        XCTAssertFalse(single.isComplete)
        XCTAssertTrue(NativeActionPresentation.fillsSingleFormSubmission(try XCTUnwrap(single.root)),
                      "A complete action group need not wait for unrelated trailing text")
    }

    @MainActor func testClassificationDoesNotChangeMessageContextOrFormPayload() async throws {
        let library = try OpenUIComponents.library()
        let examples = [
            ("root=Button(\"简短标题\",@ToAssistant(\"完整发送消息\",{topic:\"上下文\"}))", "完整发送消息"),
            ("root=Button(\"默认发送消息\")", "默认发送消息"),
            ("root=Button(\"旧协议发送消息\",{type:\"continue_conversation\",context:\"旧上下文\"})", "旧协议发送消息")
        ]
        for (source, expectedMessage) in examples {
            @MainActor func dispatch(classifying: Bool) async throws -> ActionEvent {
                let state = OpenUIState(schema: library.library.toSchema())
                state.setSource(source)
                XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
                state.setFieldValue(form: "contact", name: "email", value: .string("latest@example.invalid"), componentType: "Input")
                let element = try XCTUnwrap(state.root)
                let context = OpenUIComponentContext(element: element, registry: library.registry, state: state, formName: "contact")
                var evaluations = 0
                state.onActionEvaluation = { _ in evaluations += 1 }
                if classifying {
                    XCTAssertTrue(NativeActionPresentation.button(element).continuesConversation)
                    XCTAssertEqual(evaluations, 0, "Appearance must not evaluate the message AST")
                }
                let events = await context.triggerAction(context.string("label") ?? "", action: context.value("action"))
                XCTAssertEqual(events.count, 1)
                return try XCTUnwrap(events.first)
            }
            let before = try await dispatch(classifying: false)
            let after = try await dispatch(classifying: true)
            XCTAssertEqual(after.type, before.type)
            XCTAssertEqual(after.humanFriendlyMessage, before.humanFriendlyMessage)
            XCTAssertEqual(after.formName, before.formName)
            assertEntries(after.params, before.params)
            assertEntries(try XCTUnwrap(after.formState), try XCTUnwrap(before.formState))
            XCTAssertEqual(after.type, "continue_conversation")
            XCTAssertEqual(after.formName, "contact")
            XCTAssertEqual(after.humanFriendlyMessage, OpenUIString(expectedMessage))
            guard case .object(let form)? = after.formState?.first?.1,
                  case .object(let field)? = form["email"] else { return XCTFail("Missing submitted field") }
            XCTAssertEqual(field["value"], .string("latest@example.invalid"))
        }
    }

    private func assertEntries(_ actual: [(OpenUIString, Value)], _ expected: [(OpenUIString, Value)],
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (a, b) in zip(actual, expected) {
            XCTAssertEqual(a.0, b.0, file: file, line: line)
            XCTAssertEqual(a.1, b.1, file: file, line: line)
        }
    }
}
