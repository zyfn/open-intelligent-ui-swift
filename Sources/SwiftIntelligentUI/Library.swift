import Foundation
import SwiftLang

extension OpenUILibrary {
    /// Intelligent UI with one matched writer, historical reader, and renderer.
    public static func openIntelligentUI(
        referenceDate: Date? = nil,
        imageSearch: OpenIntelligentUIImageSearch? = nil,
        excludingComponents: Set<String> = []
    ) throws -> OpenUILibrary {
        let library = try OpenIntelligentUIComponents(referenceDate: referenceDate,
                                             imageSearch: imageSearch,
                                             excludingComponents: excludingComponents)
        return OpenUILibrary(reader: library.readerComponents, writer: library.components,
                             systemPrompt: { library.systemPrompt }) { state in
            OpenIntelligentUIContentView(state: state, library: library)
        }
    }
}
