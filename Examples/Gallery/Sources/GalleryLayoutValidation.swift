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
            OpenUIView(state: model.state, library: model.library)
                .openUIPresentation(model.presentation)
            if model.scenario == "layout-buttons" {
                Button("Arrange in row") { model.state.setState("$direction", value: .string("row")) }
                    .accessibilityIdentifier("layout.arrange-row")
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
        default: preconditionFailure("Unknown layout validation scenario: \(scenario)")
        }
    }
}
#endif
