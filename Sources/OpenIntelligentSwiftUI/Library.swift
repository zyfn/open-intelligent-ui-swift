import Foundation
import OpenUICore

extension OpenUILibrary {
    /// Intelligent UI with one matched writer, historical reader, and renderer.
    public static func intelligent(
        referenceDate: Date? = nil,
        imageSearch: IntelligentUIImageSearch? = nil,
        excludingComponents: Set<String> = []
    ) throws -> OpenUILibrary {
        let library = try IntelligentUILibrary(referenceDate: referenceDate,
                                             imageSearch: imageSearch,
                                             excludingComponents: excludingComponents)
        return OpenUILibrary(reader: library.readerComponents, writer: library.components,
                             systemPrompt: { library.systemPrompt }) { state in
            IntelligentUIView(state: state, library: library)
        }
    }
}
