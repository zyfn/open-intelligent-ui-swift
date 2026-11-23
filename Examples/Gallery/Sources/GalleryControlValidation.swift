#if DEBUG && os(iOS)
import SwiftLang
import SwiftOpenUI
import SwiftUI
import UIKit

/// Test-only host receipts expose real SDK state and native UIKit observations.
/// The UI Testing Bundle still performs the SDK controls' actual tap/typing path.
@MainActor struct GalleryControlValidationView: View {
    @StateObject private var model: GalleryControlValidationModel

    init(scenario: String) {
        _model = StateObject(wrappedValue: GalleryControlValidationModel(scenario: scenario))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let library = model.library, let state = model.state {
                OpenUIView(state: state, library: library)
                if model.scenario == "controls-selection" {
                    Button("Apply external selections") { model.applyExternalSelections() }
                        .accessibilityIdentifier("validation.controls.external")
                }
                receipt(model.stateReceipt, identifier: "validation.controls.state")
                receipt(model.actionReceipt, identifier: "validation.controls.action")
                receipt(model.nativeReceipt, identifier: "validation.controls.native")
                receipt(model.identityReceipt, identifier: "validation.controls.identity")
            }
            if let failure = model.failure {
                Text(failure).accessibilityIdentifier("validation.failure")
            }
        }
        .background(GalleryControlWindowProbe { model.window = $0 }.frame(width: 1, height: 1).opacity(0))
        .task { await model.observeNativeViews() }
    }

    private func receipt(_ value: String, identifier: String) -> some View {
        Text(value).font(.caption2).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)
    }
}

@MainActor private final class GalleryControlValidationModel: ObservableObject {
    let scenario: String
    let library: OpenUILibrary?
    let state: OpenUIState?
    weak var window: UIWindow?
    @Published private(set) var failure: String?
    @Published private(set) var stateReceipt = "Awaiting SDK state"
    @Published private(set) var actionReceipt = "count=0"
    @Published private(set) var nativeReceipt = "Awaiting UIKit"
    @Published private(set) var identityReceipt = "Awaiting document"
    private var actionCount = 0
    private var originalRoot: EvaluatedElement?
    private var originalRevision = 0
    private var initialInput: ObjectIdentifier?

    init(scenario: String) {
        self.scenario = scenario
        do {
            let library = try OpenUILibrary.openUI()
            self.library = library
            self.state = library.makeState()
        } catch {
            library = nil
            state = nil
            failure = "Control validation setup failed: \(error)"
        }
        guard let state else { return }
        state.onStateUpdate = { [weak self] _ in self?.refreshStateReceipt() }
        state.onAction = { [weak self] event in self?.record(event) }
        state.onError = { [weak self] errors in
            if !errors.isEmpty { self?.failure = "Control fixture errors: \(errors)" }
        }
        let source: String
        switch scenario {
        case "controls-selection": source = IOSNativeControlFixtures.selection
        case "controls-form": source = IOSNativeControlFixtures.form
        case "controls-slider": source = IOSNativeControlFixtures.slider
        case "controls-modal-sm": source = IOSNativeControlFixtures.modal(size: "sm")
        case "controls-modal-lg": source = IOSNativeControlFixtures.modal(size: "lg")
        default:
            failure = "Unknown control validation scene: \(scenario)"
            return
        }
        state.setSource(source)
        originalRoot = state.root
        originalRevision = state.presentationRevision
        refreshStateReceipt()
    }

    func applyExternalSelections() {
        state?.setFieldValue(form: nil, name: "pace", value: .string("easy"))
        state?.setFieldValue(form: nil, name: "route", value: .string("walk"))
        state?.setFieldValue(form: nil, name: "settings", value: .object([
            .init(key: "reminders", value: .boolean(true))
        ]))
    }

    private func refreshStateReceipt() {
        guard let state else { return }
        switch scenario {
        case "controls-selection":
            let quiet = member("quiet", of: state.fieldValue(form: nil, name: "preferences"))
            let reminders = member("reminders", of: state.fieldValue(form: nil, name: "settings"))
            stateReceipt = "pace=\(text(state.fieldValue(form: nil, name: "pace")));quiet=\(boolean(quiet));route=\(text(state.fieldValue(form: nil, name: "route")));reminders=\(boolean(reminders))"
        case "controls-form":
            stateReceipt = "email=\(text(state.fieldValue(form: "contact", name: "email")))"
        case "controls-slider":
            stateReceipt = "amount=\(text(state.fieldValue(form: "quote", name: "amount")))"
        default:
            stateReceipt = "modal-open=\(boolean(state.stateValue("$open")))"
        }
        identityReceipt = "root=\(state.root == originalRoot);revision=\(state.presentationRevision == originalRevision)"
    }

    private func record(_ event: ActionEvent) {
        actionCount += 1
        let field: OpenUIString = scenario == "controls-slider" ? "amount" : "email"
        let form = event.formState?.first?.1 ?? .null
        let value = member("value", of: member(field, of: form))
        actionReceipt = "count=\(actionCount);type=\(event.type);form=\(event.formName?.displayString ?? "");message=\(event.humanFriendlyMessage);value=\(text(value))"
    }

    /// Polling is confined to the test-only host. It observes public native
    /// objects after layout; it neither invokes an SDK action nor fabricates UI.
    func observeNativeViews() async {
        while !Task.isCancelled {
            if let window { inspectNativeViews(in: window) }
            do { try await Task.sleep(nanoseconds: 50_000_000) }
            catch { return }
        }
    }

    private func inspectNativeViews(in window: UIWindow) {
        let input = descendants(in: window).compactMap { $0 as? UITextField }.first
        if let input, initialInput == nil { initialInput = ObjectIdentifier(input) }
        let same = input.map { ObjectIdentifier($0) == initialInput } ?? false
        let keyboard = input?.keyboardType == .emailAddress ? "email" : "other"
        let receipt = "input=\(input != nil);same=\(same);focused=\(input?.isFirstResponder ?? false);keyboard=\(keyboard)"
        if nativeReceipt != receipt { nativeReceipt = receipt }

        guard scenario.hasPrefix("controls-modal-"), let state,
              state.stateValue("$open") == .boolean(true),
              let presented = presentedSheet(from: window.rootViewController),
              !presented.isBeingPresented, !presented.isBeingDismissed,
              let sheet = presented.sheetPresentationController else { return }
        let large = sheet.detents.contains { $0.identifier == .large }
        let status = "native detents=\(sheet.detents.count);large=\(large);grabber=\(sheet.prefersGrabberVisible)"
        if state.stateValue("$sheetStatus") != .string(OpenUIString(status)) {
            state.setState("$sheetStatus", value: .string(OpenUIString(status)))
        }
    }

    private func presentedSheet(from controller: UIViewController?) -> UIViewController? {
        guard let controller else { return nil }
        if let presented = controller.presentedViewController {
            if let nested = presentedSheet(from: presented) { return nested }
            if presented.viewIfLoaded?.window != nil && presented.sheetPresentationController != nil { return presented }
        }
        for child in controller.children {
            if let presented = presentedSheet(from: child) { return presented }
        }
        return nil
    }

    private func descendants(in view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants(in: $0) }
    }

    private func member(_ name: OpenUIString, of value: Value) -> Value {
        if case .object(let fields) = value { return fields[name] ?? .null }
        return .null
    }

    private func text(_ value: Value) -> String {
        switch value {
        case .string(let value): return value.displayString
        case .boolean(let value): return value ? "true" : "false"
        case .number(let value): return String(format: "%.15g", value)
        case .array(let values): return "[" + values.map(text).joined(separator: ",") + "]"
        default: return ""
        }
    }

    private func boolean(_ value: Value) -> String {
        guard case .boolean(let value) = value else { return "invalid-boolean" }
        return value ? "true" : "false"
    }
}

private struct GalleryControlWindowProbe: UIViewRepresentable {
    let attached: @MainActor (UIWindow?) -> Void
    func makeUIView(context: Context) -> GalleryControlWindowView {
        let view = GalleryControlWindowView()
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.attached = attached
        return view
    }
    func updateUIView(_ view: GalleryControlWindowView, context: Context) { view.attached = attached }
}

private final class GalleryControlWindowView: UIView {
    var attached: (@MainActor (UIWindow?) -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        attached?(window)
    }
}
#endif
