import SwiftUI
import OpenUILang

/// One client interface for a library's generation contract and native reader.
/// UI modules supply their own catalogs and presentation; Core selects neither.
public struct OpenUILibrary {
    private let reader: OpenUIComponentLibrary
    private let writer: OpenUIComponentLibrary
    private let makePrompt: () -> String
    private let makeContent: @MainActor (OpenUIState) -> AnyView

    /// Wrap an application-owned component library with the neutral Core host.
    public init(
        components: OpenUIComponentLibrary,
        promptOptions: PromptOptions = PromptOptions()
    ) {
        self.init(reader: components, writer: components,
                  systemPrompt: { components.prompt(promptOptions) }) { state in
            OpenUICoreView(state: state, registry: components.registry)
        }
    }

    /// Keep generation and historical reading matched to the same presentation.
    /// The renderer receives the host-owned state; it must not create or reset it.
    public init<Content: View>(
        reader: OpenUIComponentLibrary,
        writer: OpenUIComponentLibrary,
        systemPrompt: @escaping () -> String,
        @ViewBuilder content: @escaping @MainActor (OpenUIState) -> Content
    ) {
        self.reader = reader
        self.writer = writer
        makePrompt = systemPrompt
        makeContent = { state in AnyView(content(state)) }
    }

    /// The contract advertised to the model for new output.
    public var specification: LibrarySpec { writer.toSpec() }
    public var specificationJSON: String { specification.jsonString() }
    public var systemPrompt: String { makePrompt() }

    /// The full contract used to read stored messages, including legacy fields.
    public var readerSpecification: LibrarySpec { reader.toSpec() }

    /// Recognizes a program with this reader; this is not full contract validation.
    public func recognizesUI(in source: String) -> Bool {
        createParser(schema: reader.library.toSchema()).parse(source).root != nil
    }

    /// Create one document's state with this reader and its actual function code.
    /// Keep the returned state for the document's lifetime, including streaming.
    @MainActor public func makeState(
        toolProvider: ToolProvider? = nil,
        persistedState: [OpenUIString: Value] = [:]
    ) -> OpenUIState {
        OpenUIState(schema: reader.library.toSchema(),
                    functions: reader.library.customFunctions(),
                    toolProvider: toolProvider, persistedState: persistedState)
    }

    @MainActor @_disfavoredOverload public func makeState<S: StringProtocol & Hashable>(
        toolProvider: ToolProvider? = nil,
        persistedState: [S: Value]
    ) -> OpenUIState {
        makeState(toolProvider: toolProvider,
                  persistedState: Dictionary(persistedState.map {
                      (OpenUIString(String($0.key)), $0.value)
                  }, uniquingKeysWith: { _, new in new }))
    }

    @MainActor func content(state: OpenUIState) -> AnyView { makeContent(state) }
}

/// The common document view for every OpenUI library.
/// The selected library owns appearance; OpenUICoreView observes the state once.
@MainActor public struct OpenUIView: View {
    private let state: OpenUIState
    private let library: OpenUILibrary

    public init(state: OpenUIState, library: OpenUILibrary) {
        self.state = state
        self.library = library
    }

    public var body: some View { library.content(state: state) }
}
