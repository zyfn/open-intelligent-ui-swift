#if os(iOS)
@testable import SwiftLang
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
        owner.setSource(IOSNativeControlFixtures.input)
        ambient.setSource(IOSNativeControlFixtures.ambientInput)
        let context = OpenUIComponentContext(element: try XCTUnwrap(owner.root),
            registry: library.registry, state: owner, formName: "contact")
        let ambientContext = OpenUIComponentContext(element: try XCTUnwrap(ambient.root),
            registry: library.registry, state: ambient, formName: "contact")
        let host = try IOSNativeTestHost(VStack {
            OpenUIContextContent(context: context) { observed in
                VStack {
                    OpenUINativeField(context: observed, kind: .input)
                    IOSNativeControlUpdateLabel(text: observed.fieldValue(form: "other", name: "draft") == .string("unrelated")
                        ? "Owner update delivered" : "Owner initial", identifier: "owner-update")
                }
            }
            OpenUIContextContent(context: ambientContext) { observed in
                IOSNativeControlUpdateLabel(text: observed.fieldValue("draft") == .string("wrong owner")
                    ? "Ambient update delivered" : "Ambient initial", identifier: "ambient-update")
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
            host.descendants(of: UILabel.self).contains { $0.accessibilityIdentifier == "owner-update" && $0.text == "Owner update delivered" }
                && host.descendants(of: UILabel.self).contains { $0.accessibilityIdentifier == "ambient-update" && $0.text == "Ambient update delivered" }
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
        state.setSource(IOSNativeControlFixtures.textArea)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let host = try IOSNativeTestHost(OpenUIContentView(state: state, registry: library.registry)
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

    @MainActor func testMountedSwitchReflectsStoreUpdatesAndWritesNativeEventsWithoutReplacingTheSource() async throws {
        let library = try OpenUIComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        defer { state.reset() }
        state.setSource(IOSNativeControlFixtures.switchAndSelect)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let root = try XCTUnwrap(state.root)
        let host = try IOSNativeTestHost(OpenUIContentView(state: state, registry: library.registry)
            .environment(\.locale, Locale(identifier: "en_US")).frame(width: 360), width: 360, height: 400)
        defer { host.close() }
        try await host.waitUntil("the native UISwitch is mounted") {
            host.descendants(of: UISwitch.self).count == 1
        }
        let toggle = try XCTUnwrap(host.descendants(of: UISwitch.self).first)
        XCTAssertFalse(toggle.isOn)
        state.setFieldValue(form: nil, name: "settings", value: .object([.init(key: "reminders", value: .boolean(true))]))
        state.setFieldValue(form: nil, name: "route", value: .string("bike"))
        try await host.waitUntil("the mounted UISwitch shows its Store-only selection") { toggle.isOn }
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

    @MainActor private func edit(_ field: UITextField, text: String) {
        // Dispatch UIKit's public editing event to the mounted SwiftUI adapter.
        // Writing directly to OpenUIState would not exercise that adapter.
        field.text = text
        field.sendActions(for: .editingChanged)
    }

    @MainActor func testMountedSliderValidationFlushesTheNativeDraftSynchronously() async throws {
        let library = try OpenUIComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        defer { state.reset() }
        state.setSource(IOSNativeControlFixtures.sliderInput)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let context = OpenUIComponentContext(element: try XCTUnwrap(state.root),
            registry: library.registry, state: state, formName: "quote")
        let validation = NativeFormValidation()
        let host = try IOSNativeTestHost(OpenUINativeField(context: context, kind: .slider)
            .environment(\.openUIFormValidation, validation).frame(width: 320), width: 320, height: 260)
        defer { host.close() }
        try await host.waitUntil("the mounted slider's native numeric editor is initialized") {
            host.descendants(of: UITextField.self).first?.text == "10"
        }
        let input = try XCTUnwrap(host.descendants(of: UITextField.self).first)

        // From this point through both validations there is no suspension or
        // event-loop pump. This observes the pending native edit before debounce;
        // the separate XCUITest verifies the real submission button and payload.
        edit(input, text: "-")
        XCTAssertFalse(validation.validateAll())
        XCTAssertEqual(validation.errors["amount"], "Invalid number")
        XCTAssertEqual(input.text, "-")
        XCTAssertEqual(state.fieldValue(form: "quote", name: "amount"), .array([.number(10)]))
        edit(input, text: "37")
        XCTAssertEqual(state.fieldValue(form: "quote", name: "amount"), .array([.number(10)]),
            "The new native value must still be pending before validation")
        XCTAssertTrue(validation.validateAll())
        XCTAssertNil(validation.errors["amount"])
        XCTAssertEqual(state.fieldValue(form: "quote", name: "amount"), .array([.number(37)]))
        XCTAssertEqual(input.text, "37")
        XCTAssertTrue(host.descendants(of: UITextField.self).first === input)
    }

}

/// A real UIKit update marks the render pass without relying on the unavailable
/// in-process SwiftUI accessibility tree of a framework test runner.
private struct IOSNativeControlUpdateLabel: UIViewRepresentable {
    let text: String
    let identifier: String
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        return label
    }
    func updateUIView(_ label: UILabel, context: Context) {
        label.text = text
        label.accessibilityIdentifier = identifier
    }
}
#endif
