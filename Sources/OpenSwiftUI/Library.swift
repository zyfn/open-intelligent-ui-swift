import OpenUICore

extension OpenUILibrary {
    /// Standard components, their generation rules, and their native appearance.
    public static func standard(id: String? = nil) throws -> OpenUILibrary {
        let components = try OpenUIStandardComponents.library(id: id)
        return OpenUILibrary(reader: components, writer: components,
                             systemPrompt: { components.prompt(OpenUIStandardComponents.promptOptions) }) { state in
            OpenUIRenderer(state: state, registry: components.registry)
        }
    }
}
