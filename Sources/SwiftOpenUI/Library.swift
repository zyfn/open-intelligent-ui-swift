import SwiftLang

extension OpenUILibrary {
    /// Standard components, their generation rules, and their native appearance.
    public static func openUI(id: String? = nil) throws -> OpenUILibrary {
        let components = try OpenUIComponents.library(id: id)
        return OpenUILibrary(reader: components, writer: components,
                             systemPrompt: { components.prompt(OpenUIComponents.promptOptions) }) { state in
            OpenUIContentView(state: state, registry: components.registry)
        }
    }
}
