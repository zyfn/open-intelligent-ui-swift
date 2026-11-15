import Foundation
import SwiftLang

enum GalleryValidation {
    struct Report {
        let variants: Int
        let batchChecks: Int
        let streamChecks: Int
        let failures: [String]
    }

    @MainActor static func validate(_ catalog: GalleryCatalog) -> Report {
        var variants = 0, batchChecks = 0, streamChecks = 0
        var failures: [String] = []
        for kind in GalleryLibrary.allCases {
            do {
                let library = try kind.makeLibrary()
                var programs = try catalog.entries.filter { $0.supports(kind) }.map {
                    (id: $0.id, source: try $0.source(for: kind))
                }
                let components = try GalleryComponent.load(kind, resourceRoot: GalleryResources.root())
                programs += components.map { (id: $0.id, source: $0.source) }
                for program in programs {
                    let label = "\(program.id) [\(kind.rawValue)]"
                    variants += 1
                    let source = program.source
                    let batch = library.makeState()
                    batch.setSource(source)
                    batchChecks += 1
                    check(batch, label: label + " batch", failures: &failures)
                    batch.reset()

                    // A separate document proves streaming initialization does
                    // not inherit the batch pass's Store or parser state.
                    let stream = library.makeState()
                    let characters = Array(source)
                    for start in stride(from: 0, to: characters.count, by: 47) {
                        stream.push(String(characters[start..<min(start + 47, characters.count)]))
                        if stream.errors.contains(where: { $0.code == .parseException }) {
                            failures.append(label + " streaming parser exception")
                            break
                        }
                    }
                    stream.complete()
                    streamChecks += 1
                    check(stream, label: label + " streamed", failures: &failures)
                    stream.reset()
                }
            } catch { failures.append(kind.title + ": " + error.localizedDescription) }
        }
        return Report(variants: variants, batchChecks: batchChecks, streamChecks: streamChecks, failures: failures)
    }

    @MainActor private static func check(_ state: OpenUIState, label: String, failures: inout [String]) {
        if state.root == nil { failures.append(label + ": missing root") }
        if !state.isComplete { failures.append(label + ": incomplete document") }
        for error in state.errors { failures.append(label + ": " + error.message) }
    }

    @MainActor static func exportContracts(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for kind in GalleryLibrary.allCases {
            let json = try kind.makeLibrary().readerSpecification.jsonString()
            try json.write(to: directory.appendingPathComponent(kind.rawValue + ".json"), atomically: true, encoding: .utf8)
        }
    }
}
