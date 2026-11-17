import SwiftLang
import SwiftUI

public enum OpenUIComponents {
    /// General composition guidance for the complete native OpenUI library.
    /// Pass explicitly to prompt(_:); curate them when deriving a component subset.
    public static var promptOptions: PromptOptions { OpenUIReference.promptOptions }

    public static func library(id: String? = nil) throws -> OpenUIComponentLibrary {
        try OpenUIComponentLibrary(components: components, root: "Stack", id: id, componentGroups: OpenUIReference.groups + [ComponentGroup(name: "Maps and Diagrams", components: ["Map", "MapPoint", "SVG", "JourneyLine"], notes: ["Map displays locations, not navigation or live traffic. MapKit requires iOS 17 or macOS 14.", "SVG requires a valid viewBox. Use inline content or HTTPS src, not both; active content and external references are rejected."])])
    }
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
            }
            let registered = component.replacingDefinition(extended)
            // The upstream Steps definition has no variant. Apply the shared
            // layout contract only after the optional field has been added.
            if definition.name == "Steps" {
                return registered.presentation(layoutFields: NativeLayoutContract.fields(for: extended.name))
            }
            return registered
        }
        let all = pinned + [OpenUIGeographicComponents.map, OpenUIGeographicComponents.mapPoint, OpenUIGraphicComponents.svg, OpenUIJourneyComponents.journeyLine]
        // Use the shared core's ordinary slot extension. Existing parameter
        // positions remain unchanged; Steps only appends the optional fields above.
        do {
            let definitions = try createLibrary(components: pinned.map(\.definition)).extend(
                LibraryExtension(addComponents: Array(all.dropFirst(pinned.count)).map(\.definition), addComponentSlots: Dictionary(uniqueKeysWithValues: ["Map", "SVG", "JourneyLine"].map {
                    ($0, ["Card.children", "TabItem.content", "AccordionItem.content"])
                }))).components
            let builders = Dictionary(uniqueKeysWithValues: all.map { ($0.definition.name, $0) })
            return definitions.map { builders[$0.name]!.replacingDefinition($0) }
        } catch { preconditionFailure("Invalid SDK component library: \(error)") }
    }

}

