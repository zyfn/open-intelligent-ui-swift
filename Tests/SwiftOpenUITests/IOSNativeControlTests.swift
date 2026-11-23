#if os(iOS)
import SwiftLang
import SwiftUI
import UIKit
import XCTest
@testable import SwiftOpenUI

final class IOSNativeControlTests: XCTestCase {
    @MainActor func testMountedInputKeepsItsOwnerFocusAndSelectionAcrossUnrelatedWrites() async throws {
        let library = try OpenUIComponents.library()
        let owner = OpenUIState(schema: library.library.toSchema())
        let ambient = OpenUIState(schema: library.library.toSchema())
        defer { owner.reset(); ambient.reset() }
        owner.setSource(#"root=Input("draft",null,"text",null,"initial value")"#)
        ambient.setSource(#"root=Input("draft",null,"text",null,"ambient value")"#)
        let context = OpenUIComponentContext(element: try XCTUnwrap(owner.root),
            registry: library.registry, state: owner, formName: "contact")
        let ambientContext = OpenUIComponentContext(element: try XCTUnwrap(ambient.root),
            registry: library.registry, state: ambient, formName: "contact")
        let host = IOSNativeTestHost(VStack {
            OpenUIContextContent(context: context) { observed in
                VStack {
                    OpenUINativeField(context: observed, kind: .input)
                    Text(observed.fieldValue(form: "other", name: "draft") == .string("unrelated")
                        ? "Owner update delivered" : "Owner initial")
                }
            }
            OpenUIContextContent(context: ambientContext) { observed in
                Text(observed.fieldValue("draft") == .string("wrong owner")
                    ? "Ambient update delivered" : "Ambient initial")
            }
        }.environmentObject(ambient).frame(width: 320), width: 320, height: 220)
        defer { host.close() }
        try await host.waitUntil("the native Input has its initial owner value") {
            host.descendants(of: UITextField.self).first?.text == "initial value"
        }
        let input = try XCTUnwrap(host.descendants(of: UITextField.self).first)
        XCTAssertTrue(input.becomeFirstResponder())
        let start = try XCTUnwrap(input.position(from: input.beginningOfDocument, offset: 2))
        let end = try XCTUnwrap(input.position(from: input.beginningOfDocument, offset: 7))
        input.selectedTextRange = try XCTUnwrap(input.textRange(from: start, to: end))
        let revision = owner.presentationRevision

        owner.setFieldValue(form: "other", name: "draft", value: .string("unrelated"))
        ambient.setFieldValue(form: "contact", name: "draft", value: .string("wrong owner"))
        try await host.waitUntil("unrelated owner and ambient writes have reached the mounted hierarchy") {
            host.renderedText().contains("Owner update delivered")
                && host.renderedText().contains("Ambient update delivered")
        }
        XCTAssertTrue(host.descendants(of: UITextField.self).first === input)
        XCTAssertTrue(input.isFirstResponder)
        XCTAssertEqual(input.text, "initial value")
        let selection = try XCTUnwrap(input.selectedTextRange)
        XCTAssertEqual(input.offset(from: input.beginningOfDocument, to: selection.start), 2)
        XCTAssertEqual(input.offset(from: input.beginningOfDocument, to: selection.end), 7)

        edit(input, text: "typed through UIKit")
        try await host.waitUntil("native editingChanged writes to the owning form") {
            owner.fieldValue(form: "contact", name: "draft") == .string("typed through UIKit")
        }
        XCTAssertEqual(ambient.fieldValue(form: "contact", name: "draft"), .string("wrong owner"))
        XCTAssertTrue(input.resignFirstResponder())
        owner.setFieldValue(form: "contact", name: "draft", value: .string("updated owner value"))
        try await host.waitUntil("the mounted Input receives an external owner update") {
            input.text == "updated owner value"
        }
        XCTAssertTrue(host.descendants(of: UITextField.self).first === input)
        XCTAssertEqual(owner.presentationRevision, revision)
        try host.saveSnapshot(name: "input-owner-update")
    }

    @MainActor func testMountedTextAreaEditsAndExternalUpdatesUseTheSameNativeEditor() async throws {
        let library = try OpenUIComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        defer { state.reset() }
        state.setSource(#"root=TextArea("notes","Write notes",3,null,"Initial notes")"#)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let host = IOSNativeTestHost(OpenUIContentView(state: state, registry: library.registry)
            .frame(width: 360), width: 360, height: 320)
        defer { host.close() }
        try await host.waitUntil("the native TextEditor displays its initial value") {
            host.descendants(of: UITextView.self).contains { $0.isEditable && $0.text == "Initial notes" }
        }
        let editor = try XCTUnwrap(host.descendants(of: UITextView.self).first(where: \.isEditable))
        XCTAssertTrue(editor.becomeFirstResponder())
        editor.selectedRange = NSRange(location: 0, length: editor.text.utf16.count)
        editor.insertText("Native multiline edit\nSecond line")
        try await host.waitUntil("native text insertion updates the SDK field") {
            state.fieldValue(form: nil, name: "notes") == .string("Native multiline edit\nSecond line")
        }
        XCTAssertTrue(editor.isFirstResponder)
        XCTAssertTrue(host.descendants(of: UITextView.self).first(where: \.isEditable) === editor)
        XCTAssertTrue(editor.resignFirstResponder())
        state.setFieldValue(form: nil, name: "notes", value: .string("External notes\nKept in the same editor"))
        try await host.waitUntil("the same TextEditor receives an external value") {
            editor.text == "External notes\nKept in the same editor"
        }
        XCTAssertTrue(host.descendants(of: UITextView.self).first(where: \.isEditable) === editor)
        try host.saveSnapshot(name: "textarea-external-update")
    }

    @MainActor func testMountedSwitchAndSelectReflectStoreUpdatesWithoutReplacingTheSource() async throws {
        let library = try OpenUIComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        defer { state.reset() }
        state.setSource(#"root=Stack([SwitchGroup("settings",[SwitchItem("Reminders","","reminders",false)]),Select("route",[SelectItem("walk","Walk"),SelectItem("bike","Bike")],"Choose route")])"#)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let root = try XCTUnwrap(state.root)
        let host = IOSNativeTestHost(OpenUIContentView(state: state, registry: library.registry)
            .environment(\.locale, Locale(identifier: "en_US")).frame(width: 360), width: 360, height: 400)
        defer { host.close() }
        try await host.waitUntil("the native switch and select are mounted") {
            host.descendants(of: UISwitch.self).count == 1
                && host.accessibilityElements().contains { $0.accessibilityValue == "Choose route" }
        }
        let toggle = try XCTUnwrap(host.descendants(of: UISwitch.self).first)
        XCTAssertFalse(toggle.isOn)
        state.setFieldValue(form: nil, name: "settings", value: .object([.init(key: "reminders", value: .boolean(true))]))
        state.setFieldValue(form: nil, name: "route", value: .string("bike"))
        try await host.waitUntil("mounted switch and select show their Store-only selections") {
            toggle.isOn && host.accessibilityElements().contains { $0.accessibilityValue == "Bike" }
        }
        XCTAssertEqual(state.root, root, "These selections are absent from the component props")
        XCTAssertTrue(host.descendants(of: UISwitch.self).first === toggle)
        try host.saveSnapshot(name: "switch-and-select-store-update")

        toggle.setOn(false, animated: false)
        toggle.sendActions(for: .valueChanged)
        try await host.waitUntil("the real UISwitch event writes its off value") {
            state.fieldValue(form: nil, name: "settings") == .object([.init(key: "reminders", value: .boolean(false))])
        }
        XCTAssertEqual(state.fieldValue(form: nil, name: "route"), .string("bike"))
        XCTAssertEqual(state.root, root)
    }

    @MainActor func testMountedRadioAndCheckboxActionsUpdateSelectionAndAccessibility() async throws {
        let library = try OpenUIComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        defer { state.reset() }
        state.setSource(#"root=Stack([RadioGroup("pace",[RadioItem("Easy","","easy"),RadioItem("Full","","full")],"easy"),CheckBoxGroup("preferences",[CheckBoxItem("Quiet","","quiet",false)])])"#)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let host = IOSNativeTestHost(OpenUIContentView(state: state, registry: library.registry)
            .environment(\.locale, Locale(identifier: "en_US")).frame(width: 360), width: 360, height: 400)
        defer { host.close() }
        try await host.waitUntil("radio and checkbox native accessibility actions are mounted") {
            self.button("Full", in: host) != nil && self.button("Quiet", in: host) != nil
        }
        XCTAssertTrue(try XCTUnwrap(button("Easy", in: host)).accessibilityTraits.contains(.selected))
        XCTAssertTrue(try XCTUnwrap(button("Full", in: host)).accessibilityActivate())
        try await host.waitUntil("radio activation selects Full") {
            state.fieldValue(form: nil, name: "pace") == .string("full")
                && self.button("Full", in: host)?.accessibilityTraits.contains(.selected) == true
        }
        XCTAssertFalse(try XCTUnwrap(button("Easy", in: host)).accessibilityTraits.contains(.selected))
        XCTAssertTrue(try XCTUnwrap(button("Quiet", in: host)).accessibilityActivate())
        try await host.waitUntil("checkbox activation selects Quiet") {
            state.fieldValue(form: nil, name: "preferences") == .object([.init(key: "quiet", value: .boolean(true))])
                && self.button("Quiet", in: host)?.accessibilityTraits.contains(.selected) == true
        }
        state.setFieldValue(form: nil, name: "pace", value: .string("easy"))
        try await host.waitUntil("external radio selection updates the existing accessibility tree") {
            self.button("Easy", in: host)?.accessibilityTraits.contains(.selected) == true
                && self.button("Full", in: host)?.accessibilityTraits.contains(.selected) == false
        }
        try host.saveSnapshot(name: "radio-and-checkbox-selection")
    }

    @MainActor func testMountedFormBlocksInvalidSubmissionAndDispatchesTheEditedField() async throws {
        let library = try OpenUIComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        defer { state.reset() }
        state.setSource(#"root=Form("contact",Buttons([Button("Send",@ToAssistant("Contact details"))]),[FormControl("Email",Input("email","Email address","email",{required:true,email:true}))])"#)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        var events: [ActionEvent] = []
        state.onAction = { events.append($0) }
        let host = IOSNativeTestHost(OpenUIContentView(state: state, registry: library.registry)
            .environment(\.locale, Locale(identifier: "en_US")).frame(width: 360), width: 360, height: 460)
        defer { host.close() }
        try await host.waitUntil("the form Input and submission action are mounted") {
            host.descendants(of: UITextField.self).count == 1 && self.button("Send", in: host) != nil
        }
        let input = try XCTUnwrap(host.descendants(of: UITextField.self).first)
        XCTAssertEqual(input.keyboardType, .emailAddress)
        XCTAssertTrue(try XCTUnwrap(button("Send", in: host)).accessibilityActivate())
        try await host.waitUntil("invalid submission displays an error and focuses its native Input") {
            input.isFirstResponder && self.element("openui.error.email", in: host) != nil
        }
        XCTAssertTrue(events.isEmpty, "Invalid native forms must not emit host actions")
        try host.saveSnapshot(name: "form-invalid-focused")
        edit(input, text: "native@example.invalid")
        try await host.waitUntil("native editing clears field feedback") {
            state.fieldValue(form: "contact", name: "email") == .string("native@example.invalid")
                && self.element("openui.error.email", in: host) == nil
        }
        XCTAssertTrue(host.descendants(of: UITextField.self).first === input)
        XCTAssertTrue(try XCTUnwrap(button("Send", in: host)).accessibilityActivate())
        try await host.waitUntil("the real form action reaches its host") { events.count == 1 }
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.type, "continue_conversation")
        XCTAssertEqual(event.formName, "contact")
        XCTAssertEqual(event.humanFriendlyMessage, "Contact details")
        XCTAssertEqual(try submittedValue("email", event: event), .string("native@example.invalid"))
        try host.saveSnapshot(name: "form-valid-submitted")
    }

    @MainActor func testMountedSliderKeepsInvalidDraftLocalAndFlushesTheCorrectedValueOnSubmit() async throws {
        let library = try OpenUIComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        defer { state.reset() }
        state.setSource(#"root=Form("quote",Buttons([Button("Send amount",@ToAssistant("Amount details"))]),[FormControl("Budget",Slider("amount","continuous",0,100,1,[10],"Budget"))])"#)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        var events: [ActionEvent] = []
        state.onAction = { events.append($0) }
        let host = IOSNativeTestHost(OpenUIContentView(state: state, registry: library.registry)
            .environment(\.locale, Locale(identifier: "en_US")).frame(width: 360), width: 360, height: 520)
        defer { host.close() }
        try await host.waitUntil("the slider endpoint and submission action are mounted") {
            host.descendants(of: UITextField.self).first?.text == "10"
                && self.button("Send amount", in: host) != nil
        }
        let input = try XCTUnwrap(host.descendants(of: UITextField.self).first)
        XCTAssertTrue(input.becomeFirstResponder())
        edit(input, text: "-")
        XCTAssertTrue(try XCTUnwrap(button("Send amount", in: host)).accessibilityActivate())
        try await host.waitUntil("the invalid numeric draft is displayed beside the slider") {
            self.element("openui.error.amount", in: host) != nil
        }
        XCTAssertEqual(input.text, "-")
        XCTAssertEqual(state.fieldValue(form: "quote", name: "amount"), .array([.number(10)]))
        XCTAssertTrue(events.isEmpty, "An invalid draft cannot submit the previous numeric value")
        try host.saveSnapshot(name: "slider-invalid-draft")

        // No wait for the draft debounce: the real form action must flush it.
        edit(input, text: "37")
        XCTAssertTrue(try XCTUnwrap(button("Send amount", in: host)).accessibilityActivate())
        try await host.waitUntil("submission flushes the latest native numeric edit") { events.count == 1 }
        XCTAssertEqual(state.fieldValue(form: "quote", name: "amount"), .array([.number(37)]))
        XCTAssertEqual(try submittedValue("amount", event: XCTUnwrap(events.first)), .array([.number(37)]))
        XCTAssertTrue(host.descendants(of: UITextField.self).first === input)
        try host.saveSnapshot(name: "slider-valid-submitted")
    }

    @MainActor func testMountedSmallModalUsesNativeDetentsAndCloseWritesItsBinding() async throws {
        try await assertModal(size: "sm", expectedDetents: 2)
    }

    @MainActor func testMountedLargeModalUsesOnlyTheLargeDetentAndCloseWritesItsBinding() async throws {
        try await assertModal(size: "lg", expectedDetents: 1)
    }

    @MainActor private func assertModal(size: String, expectedDetents: Int) async throws {
        let library = try OpenUIComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        defer { state.reset() }
        state.setSource("$open=false\nroot=Stack([TextContent(\"Underlying page\"),Modal(\"Details\",$open,[TextContent(\"Inside the modal\")],\"\(size)\")])")
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let host = IOSNativeTestHost(OpenUIContentView(state: state, registry: library.registry)
            .environment(\.locale, Locale(identifier: "en_US")).frame(width: 390), width: 390, height: 844)
        defer { host.close() }
        try await host.waitUntil("the modal's underlying page is mounted") {
            host.renderedText().contains("Underlying page")
        }
        XCTAssertNil(host.controller.presentedViewController)
        state.setState("$open", value: .boolean(true))
        try await host.waitUntil("the native sheet presents its content and close action") {
            host.controller.presentedViewController?.view.window != nil
                && host.renderedText().contains("Inside the modal")
                && self.button("Close", in: host) != nil
        }
        let presented = try XCTUnwrap(host.controller.presentedViewController)
        let sheet = try XCTUnwrap(presented.sheetPresentationController)
        XCTAssertEqual(sheet.detents.count, expectedDetents)
        XCTAssertTrue(sheet.detents.contains { $0.identifier == .large })
        XCTAssertTrue(sheet.prefersGrabberVisible)
        XCTAssertEqual(state.stateValue("$open"), .boolean(true))
        try host.saveSnapshot(name: "modal-\(size)-presented", view: presented.view)
        XCTAssertTrue(try XCTUnwrap(button("Close", in: host)).accessibilityActivate())
        try await host.waitUntil("native Close dismisses the sheet and clears its Lang binding") {
            host.controller.presentedViewController == nil && state.stateValue("$open") == .boolean(false)
        }
        XCTAssertTrue(host.renderedText().contains("Underlying page"))
    }

    @MainActor private func edit(_ field: UITextField, text: String) {
        // Dispatch UIKit's public editing event to the mounted SwiftUI adapter.
        // Writing directly to OpenUIState would not exercise that adapter.
        field.text = text
        field.sendActions(for: .editingChanged)
    }

    @MainActor private func button(_ label: String, in host: IOSNativeTestHost) -> NSObject? {
        host.accessibilityElements().first {
            $0.accessibilityLabel == label && $0.accessibilityTraits.contains(.button)
        }
    }

    @MainActor private func element(_ identifier: String, in host: IOSNativeTestHost) -> NSObject? {
        host.accessibilityElements().first {
            ($0 as? UIAccessibilityIdentification)?.accessibilityIdentifier == identifier
        }
    }

    private func submittedValue(_ name: OpenUIString, event: ActionEvent) throws -> Value {
        guard case .object(let form)? = event.formState?.first?.1,
            case .object(let field)? = form[name] else {
            XCTFail("Missing submitted form field \(name)")
            throw MissingSubmission.field
        }
        return try XCTUnwrap(field["value"])
    }

    private enum MissingSubmission: Error { case field }
}
#endif
