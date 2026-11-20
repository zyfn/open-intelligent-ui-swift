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
        let resourceRoot: URL
        do {
            resourceRoot = try GalleryResources.root()
            _ = try GalleryDesignSystem.load(resourceRoot: resourceRoot)
        } catch {
            return Report(variants: 0, batchChecks: 0, streamChecks: 0, failures: [error.localizedDescription])
        }
        for kind in GalleryLibrary.allCases {
            do {
                let library = try kind.makeLibrary()
                var programs = try catalog.entries.filter { $0.supports(kind) }.map {
                    (id: $0.id, source: try $0.source(for: kind), component: nil as GalleryComponent?)
                }
                let components = try GalleryComponent.load(kind, resourceRoot: resourceRoot)
                let supporting = components.filter { $0.container != nil }
                let supportingByPreview = Dictionary(grouping: supporting, by: \.previewRoot)
                var shown = Set<String>()
                programs += components.filter { $0.container == nil }.flatMap { owner in
                    owner.examples.map { (id: owner.id + "/" + $0.id, source: $0.program, component: owner) }
                }
                for program in programs {
                    let label = "\(program.id) [\(kind.rawValue)]"
                    variants += 1
                    let source = program.source
                    let batch = library.makeState()
                    batch.setSource(source)
                    batchChecks += 1
                    check(batch, label: label + " batch", failures: &failures)
                    if let component = program.component, let root = batch.root {
                        if !contains(component.name, root: root) {
                            failures.append(label + ": 示例没有使用 \(component.name)")
                        }
                        for child in supportingByPreview[component.name, default: []] {
                            if contains(child.name, in: child.container, root: root) { shown.insert(child.name) }
                        }
                    }
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
                for item in supporting where !shown.contains(item.name) {
                    failures.append("\(kind.title): \(item.previewRoot) 的示例中缺少从属项 \(item.name)")
                }
            } catch { failures.append(kind.title + ": " + error.localizedDescription) }
        }
        return Report(variants: variants, batchChecks: batchChecks, streamChecks: streamChecks, failures: failures)
    }

    static func contains(_ name: String, in parent: String? = nil, root: EvaluatedElement) -> Bool {
        func elements(_ value: Value) -> [EvaluatedElement] {
            switch value {
            case .element(let node): return [node]
            case .array(let values): return values.flatMap(elements)
            case .object(let fields): return fields.flatMap { elements($0.value) }
            default: return []
            }
        }
        let children = root.props.flatMap { elements($0.1) }
        return (parent == nil && root.typeName == name)
            || (root.typeName == parent && children.contains { $0.typeName == name })
            || children.contains { contains(name, in: parent, root: $0) }
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
