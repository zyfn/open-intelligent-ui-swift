import Foundation
import SwiftLang

/// One catalog supplies generation contracts and backwards-compatible reading.
public struct OpenIntelligentUIComponents {
    /// Components available to new model output and exported contracts.
    public let components: OpenUIComponentLibrary
    /// Existing messages keep the full SDK reader; never exported to the model.
    let readerComponents: OpenUIComponentLibrary
    let excludedComponentNames: Set<String>

    public init(referenceDate: Date? = nil, imageSearch: OpenIntelligentUIImageSearch? = nil, excludingComponents: Set<String> = []) throws {
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
            throw NSError(domain: "OpenIntelligentUI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot exclude unknown components or the Col root: " + invalid.sorted().joined(separator: ", ")])
        }
        let complete = try OpenUIComponentLibrary(
            components: supplied,
            functions: functions,
            actions: [DefinedAction(name: "CopyToClipboard", description: "Request copying text through the caller's action handler.", params: [OpenUIParameter.string("text")])],
            root: "Col", id: "openintelligentui"
        )
        readerComponents = complete
        excludedComponentNames = excludingComponents
        components = try OpenUIComponentLibrary(
            // Keep stored ImageText programs readable; new output composes
            // Image and text with the ordinary layout components.
            components: supplied.filter {
                $0.definition.name != "ImageText" && !excludingComponents.contains($0.definition.name)
            }.map(WriterContract.project),
            functions: functions, actions: complete.library.actions,
            root: complete.library.root, id: complete.library.id
        )
    }

    /// Detect a UI program using the full reader catalog, including components
    /// excluded from new generation. This is parsing, not contract validation.
    public func recognizesUI(in source: String) -> Bool {
        OpenUILibrary(components: readerComponents).recognizesUI(in: source)
    }

    /// Convenience factory for SDK state; ownership remains with the caller.
    @MainActor public func makeState() -> OpenUIState {
        OpenUILibrary(components: readerComponents).makeState()
    }
}
