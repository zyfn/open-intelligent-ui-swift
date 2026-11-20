import SwiftLang
import SwiftUI

public enum OpenUIComponents {
    /// General composition guidance for the complete native OpenUI library.
    /// Pass explicitly to prompt(_:); curate them when deriving a component subset.
    public static var promptOptions: PromptOptions { OpenUIReference.promptOptions }

    public static func library(id: String? = nil) throws -> OpenUIComponentLibrary {
        try OpenUIComponentLibrary(components: components, root: "Stack", id: id, componentGroups: componentGroups)
    }

    private static let componentGroups: [ComponentGroup] = {
        func notes(_ groups: String...) -> [String] {
            groups.flatMap { name in
                OpenUIReference.groups.first { $0.name == name }?.notes ?? []
            }
        }
        let layoutNotes = notes("Layout")
        let contentNotes = notes("Content")
        let dataNotes = notes("Data Display")
        let switchingNotes = layoutNotes.filter { $0.hasPrefix("- Modal(") }
        let containerNotes = contentNotes.filter { $0.hasPrefix("- Use Stack ") }
        let mediaNotes = contentNotes.filter { $0.hasPrefix("- Image") }
        let tagNotes = dataNotes.filter { $0.hasPrefix("- Color-mapped Tag:") }
        return [
            ComponentGroup(name: "Layout and Containers",
                components: ["Stack", "Card", "Separator"],
                notes: layoutNotes.filter { !switchingNotes.contains($0) } + containerNotes),
            ComponentGroup(name: "Browsing and Switching",
                components: ["Tabs", "TabItem", "Carousel", "Accordion", "AccordionItem", "Modal"],
                notes: switchingNotes),
            ComponentGroup(name: "Text and Labels",
                components: [
                    "TextContent", "MarkDownRenderer", "CardHeader", "InlineHeader", "CodeBlock",
                    "TextCallout", "Callout", "Text", "BoldText", "IconText", "Tag", "TagBlock", "Icon"
                ],
                notes: contentNotes.filter { !containerNotes.contains($0) && !mediaNotes.contains($0) } + tagNotes),
            ComponentGroup(name: "Media",
                components: ["Image", "ImageBlock", "ImageGallery"],
                notes: mediaNotes),
            ComponentGroup(name: "Lists and Object Cards",
                components: [
                    "EntityList", "ListBlock", "ListItem", "Steps", "StepsItem", "ImageText", "ImageTextLarge",
                    "SnippetCardBlock", "SnippetCardItem", "OverviewCardBlock", "OverviewCardItem",
                    "ContextCardBlock", "ContextCardItem", "CompositeCardBlock", "CompositeCardItem",
                    "VisualCardBlock", "VisualCardItem"
                ],
                notes: dataNotes.filter { !tagNotes.contains($0) } + notes("Cards")),
            ComponentGroup(name: "Tables, Charts and Metrics",
                components: [
                    "Table", "Col", "EditableTable", "BarChart", "HorizontalBarChart", "LineChart",
                    "AreaChart", "RadarChart", "Series", "PieChart", "RadialChart", "SingleStackedBarChart",
                    "Slice", "ScatterChart", "ScatterSeries", "Point",
                    "MetricIndicatorInline", "MetricIndicatorWithStrikethrough"
                ],
                notes: notes("Tables", "Charts (2D)", "Charts (1D)", "Charts (Scatter)")),
            ComponentGroup(name: "Maps and Diagrams",
                components: ["Map", "MapPoint", "SVG", "JourneyLine"],
                notes: [
                    "Map displays locations, not navigation or live traffic. MapKit requires iOS 17 or macOS 14.",
                    "SVG requires a valid viewBox. Use inline content or HTTPS src, not both; active content and external references are rejected."
                ]),
            ComponentGroup(name: "Forms and Actions",
                components: [
                    "Form", "FormControl", "Label", "Input", "TextArea", "Select", "SelectItem",
                    "DatePicker", "Slider", "CheckBoxGroup", "CheckBoxItem", "RadioGroup", "RadioItem",
                    "SwitchGroup", "SwitchItem", "Chips", "ChipItem", "OptionCards", "OptionCard",
                    "Button", "Buttons", "IconButton", "FollowUpBlock", "FollowUpItem"
                ],
                notes: notes("Forms", "Buttons"))
        ]
    }()

    public static var components: [OpenUIComponent] {
        let implementations = OpenUISelectionComponents.components + OpenUIFormComponents.components
            + OpenUIDisplayComponents.components + OpenUIContentComponents.components
            + OpenUIChartComponents.components + [
            OpenUIReference.component("Stack") {
                OpenUIStack(context: $0, wrapJustifyBetweenAsStart: true)
            },
            OpenUIReference.component("TextContent") { context in
                NativeMarkdownText(text: context.string("text") ?? "", mode: .textContent,
                    style: .textContent(context.presentationString("size"), theme: context.theme))
            },
            OpenUIReference.component("Image") { NativeContentImage(context: $0) },
            OpenUIReference.component("Button") { OpenUINativeButton(context: $0) },
            OpenUIReference.component("Card") { OpenUIStyledCard(context: $0) }
        ]
        let byName = Dictionary(uniqueKeysWithValues: implementations.map { ($0.definition.name, $0) })
        let pinned = OpenUIReference.definitions.map { definition in
            guard let component = byName[definition.name] else { preconditionFailure("Missing native renderer: " + definition.name) }
            var extended = definition
            if definition.name == "Steps" {
                extended.params.append(OpenUIParameter.string("variant", required: false, values: ["default", "timeline"]))
                extended.description += " Use timeline for chronological events; omit variant for numbered instructions."
            } else if definition.name == "StepsItem" {
                extended.params.append(OpenUIParameter.string("time", required: false))
                extended.description += " Optional time is shown in timeline when known; do not invent times."
            } else if definition.name == "Tabs" {
                extended.params.append(OpenUIParameter.string("variant", required: false, values: ["default", "date"]))
                extended.description += ". Opens the first item in display order and keeps the selected page as content arrives. Use date to switch calendar days, with a unique YYYY-MM-DD value and a short weekday trigger per TabItem. Omit variant for ordinary topic tabs."
            }
            let registered = component.replacingDefinition(extended)
            // Register native layout dependencies after extending the upstream definitions.
            if definition.name == "Steps" || definition.name == "Tabs" {
                return registered.presentation(layoutFields: NativeLayoutContract.fields(for: extended.name))
            }
            return registered
        }
        let all = pinned + [OpenUIGeographicComponents.map, OpenUIGeographicComponents.mapPoint, OpenUIGraphicComponents.svg, OpenUIJourneyComponents.journeyLine]
        // Use the shared core's ordinary slot extension. Existing parameter
        // positions are retained when optional fields are appended above.
        do {
            let definitions = try createLibrary(components: pinned.map(\.definition)).extend(
                LibraryExtension(addComponents: Array(all.dropFirst(pinned.count)).map(\.definition), addComponentSlots: Dictionary(uniqueKeysWithValues: ["Map", "SVG", "JourneyLine"].map {
                    ($0, ["Card.children"])
                }))).components
            let builders = Dictionary(uniqueKeysWithValues: all.map { ($0.definition.name, $0) })
            return definitions.map { builders[$0.name]!.replacingDefinition($0) }
        } catch { preconditionFailure("Invalid SDK component library: \(error)") }
    }

}

