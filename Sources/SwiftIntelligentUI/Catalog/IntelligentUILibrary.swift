import Foundation
import OpenUILang
import OpenUISwiftUI

/// Public names let hosts depend on this SDK without importing runtime modules.
public typealias IntelligentUIState = OpenUIState
public typealias IntelligentUIActionEvent = ActionEvent

/// One catalog supplies generation contracts and backwards-compatible reading.
public struct IntelligentUILibrary {
    /// Components available to new model output and exported contracts.
    public let components: OpenUIComponentLibrary
    /// Existing messages keep the full SDK reader; never exported to the model.
    let readerComponents: OpenUIComponentLibrary
    let excludedComponentNames: Set<String>

    public init(referenceDate: Date? = nil, imageSearch: IntelligentUIImageSearch? = nil, excludingComponents: Set<String> = []) throws {
        let functions = try FunctionLibrary(fixedNow: referenceDate).definitions()
        let math = try MathTypesetter()
        var supplied = [ColumnComponent.component, RowComponent.component, GridComponent.component, BoxComponent.component, CardComponent.component,
                        TextComponent.component, TitleComponent.component, CheckboxComponent.component, ButtonComponent.component,
                        SliderComponent.component, ImageComponent.component, IconComponent.component, CaptionComponent.component,
                        LabelComponent.component, LinkComponent.component, InputComponent.component, TextAreaComponent.component,
                        SelectComponent.component, SegmentedControlComponent.component, RadioGroupComponent.component, ProductCardComponent.component, TransportCardComponent.component,
                        MarkdownComponent.component, QuoteComponent.component, CodeComponent.component, BadgeComponent.component, ImageTextComponent.component, CitationComponent.component,
                        ListComponent.component, ListItemComponent.component, TableComponent.component, ChartComponent.component, ProgressComponent.component,
                        DividerComponent.component, SpacerComponent.component, CarouselComponent.component, FormComponent.component,
                        PopoverComponent.component, DisclosureComponent.component, IconButtonComponent.component, PressableComponent.component,
                        DatePickerComponent.component, TimerComponent.component, FlashcardComponent.component, CelebrationComponent.component,
                        MathComponent.component(typesetter: math), MapComponent.component, MapMarkerComponent.component,
                        HtmlViewComponent.component, YouTubeComponent.component] + SVGComponents.components
        if let imageSearch { supplied.append(SearchImageComponent.component(provider: imageSearch)) }
        let known = Set(supplied.map(\.definition.name)).union(["SearchImage"])
        let invalid = excludingComponents.subtracting(known).union(excludingComponents.intersection(["Col"]))
        guard invalid.isEmpty else {
            throw NSError(domain: "SwiftIntelligentUI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot exclude unknown components or the Col root: " + invalid.sorted().joined(separator: ", ")])
        }
        let complete = try OpenUIComponentLibrary(
            components: supplied,
            functions: functions,
            actions: [DefinedAction(name: "CopyToClipboard", description: "Request copying text through the caller's action handler.", params: [OpenUIParameter.string("text")])],
            root: "Col", id: "swift-intelligent-ui.v0.1"
        )
        readerComponents = complete
        excludedComponentNames = excludingComponents
        let removing = excludingComponents.intersection(Set(supplied.map(\.definition.name)))
        components = removing.isEmpty ? complete : try complete.extending(removing: removing.sorted())
    }

    /// Detect a UI program using the full reader catalog, including components
    /// excluded from new generation. This is parsing, not contract validation.
    public func recognizesUI(in source: String) -> Bool {
        createParser(schema: readerComponents.library.toSchema()).parse(source).root != nil
    }

    /// Convenience factory for SDK state; ownership remains with the caller.
    @MainActor public func makeState() -> OpenUIState {
        OpenUIState(schema: readerComponents.library.toSchema(), functions: readerComponents.library.customFunctions())
    }
}
