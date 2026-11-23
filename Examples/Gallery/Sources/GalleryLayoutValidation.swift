#if DEBUG && os(iOS)
import SwiftUI
import SwiftLang
import SwiftOpenUI

/// UI automation renders the same programs as IOSNativeLayoutTests through the
/// public SDK entry. Viewport and accessibility settings belong to the host.
@MainActor struct GalleryLayoutValidationView: View {
    @StateObject private var model: GalleryLayoutValidationModel

    init(scenario: String) {
        _model = StateObject(wrappedValue: GalleryLayoutValidationModel(scenario: scenario))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.scenario == "layout-pager" {
                // Give the surrounding real ScrollView room in both directions
                // while the carousel remains visible during a vertical drag.
                Text("Reading before the carousel")
                    .frame(height: 160, alignment: .bottomLeading)
                    .accessibilityIdentifier("layout.pager.before")
            }
            OpenUIView(state: model.state, library: model.library)
                .openUIPresentation(model.presentation)
            if model.scenario == "layout-buttons" {
                Button("Arrange in row") { model.state.setState("$direction", value: .string("row")) }
                    .accessibilityIdentifier("layout.arrange-row")
            }
            if model.scenario == "layout-pager" {
                Text("Reading after the carousel")
                    .accessibilityIdentifier("layout.pager.after")
                ForEach(1...14, id: \.self) { paragraph in
                    Text("Following paragraph \(paragraph). The surrounding document remains vertically scrollable.")
                }
            }
        }
    }
}

@MainActor private final class GalleryLayoutValidationModel: ObservableObject {
    let scenario: String
    let library: OpenUILibrary
    let state: OpenUIState
    let presentation: OpenUIPresentation

    init(scenario: String) {
        self.scenario = scenario
        do { library = try .openUI() }
        catch { preconditionFailure("Cannot create layout validation library: \(error)") }
        state = library.makeState()
        var presentation = OpenUIPresentation()
        presentation.minimumChoiceWidth = 200
        self.presentation = presentation
        switch scenario {
        case "layout-composite": state.setSource(IOSNativeLayoutFixtures.compositeCards)
        case "layout-buttons": state.setSource(IOSNativeLayoutFixtures.buttons)
        case "layout-options": state.setSource(IOSNativeLayoutFixtures.options)
        case "layout-pager": state.setSource(IOSNativeLayoutFixtures.pager)
        default: preconditionFailure("Unknown layout validation scenario: \(scenario)")
        }
    }
}
#endif
