import Foundation
import SwiftLang

enum GalleryValidation {
    /// The SDK receives decoded Strings. Scalar partitions can split a
    /// grapheme, an escape or a Lang token without creating invalid UTF-16.
    enum StreamPartition: String, CaseIterable {
        case characters47 = "characters-47"
        case scalarPattern = "scalars-1-7-24-128"
        case syntaxBoundaries = "syntax-boundaries"

        func chunks(_ source: String) -> [String] {
            if self == .characters47 {
                let characters = Array(source)
                return stride(from: 0, to: characters.count, by: 47).map {
                    String(characters[$0..<min($0 + 47, characters.count)])
                }
            }
            let scalars = Array(source.unicodeScalars)
            var chunks: [String] = []
            var start = 0, index = 0
            let pattern = [1, 7, 24, 128]
            let delimiters = Set("\"\\()[]{},=\n".unicodeScalars)
            while start < scalars.count {
                var end = min(start + pattern[index % pattern.count], scalars.count)
                if self == .syntaxBoundaries {
                    // Prefer a real token boundary after a minimum span of
                    // scalars. Do not replay every prefix of long cases.
                    end = min(start + 128, scalars.count)
                    if let boundary = (min(start + 24, end)..<end).first(where: {
                        delimiters.contains(scalars[$0])
                    }) { end = boundary + (index.isMultiple(of: 2) ? 0 : 1) }
                }
                chunks.append(String(String.UnicodeScalarView(scalars[start..<end])))
                start = end
                index += 1
            }
            return chunks
        }
    }

    struct TerminalSnapshot {
        let root: Value?
        let state: [OpenUIString: Value]
        let complete: Bool
        let interrupted: Bool
        let meta: ParseMeta?

        @MainActor init(_ document: OpenUIState, meta: ParseMeta?) {
            root = document.root.map { GalleryValidation.semanticValue(.element($0)) }
            state = document.snapshotState().mapValues(GalleryValidation.semanticValue)
            complete = document.isComplete
            interrupted = document.isInterrupted
            self.meta = meta
        }
    }

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
                    var batchMeta: ParseMeta?
                    batch.onParseResult = { batchMeta = $0.meta }
                    batch.setSource(source)
                    batchChecks += 1
                    check(batch, meta: batchMeta, label: label + " batch", failures: &failures)
                    if let component = program.component, let root = batch.root {
                        if !contains(component.name, root: root) {
                            failures.append(label + ": 示例没有使用 \(component.name)")
                        }
                        for child in supportingByPreview[component.name, default: []] {
                            if contains(child.name, in: child.container, root: root) { shown.insert(child.name) }
                        }
                    }
                    let expected = TerminalSnapshot(batch, meta: batchMeta)
                    batch.reset()

                    for partition in StreamPartition.allCases {
                        let streamLabel = label + " streamed/" + partition.rawValue
                        // Every schedule has its own document, Store and parser.
                        let stream = library.makeState()
                        var streamMeta: ParseMeta?
                        stream.onParseResult = { streamMeta = $0.meta }
                        for chunk in partition.chunks(source) {
                            stream.push(chunk)
                            if stream.errors.contains(where: { $0.code == .parseException }) {
                                failures.append(streamLabel + ": streaming parser exception")
                                break
                            }
                        }
                        stream.complete()
                        streamChecks += 1
                        check(stream, meta: streamMeta, label: streamLabel, failures: &failures)
                        failures += terminalDifferences(TerminalSnapshot(stream, meta: streamMeta), from: expected)
                            .map { streamLabel + ": " + $0 }
                        stream.reset()
                    }
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

    /// Compare all content and prop values, including action steps, binding
    /// targets/transforms and ordered objects. Node identity and native parser
    /// caches/readiness metadata are not part of the Lang result.
    private static func semanticValue(_ value: Value) -> Value {
        switch value {
        case .element(let element):
            return .element(EvaluatedElement(typeName: element.typeName,
                props: element.props.map { ($0.0, semanticValue($0.1)) }, partial: element.partial))
        case .array(let values): return .array(values.map(semanticValue))
        case .object(let fields):
            return .object(fields.map { ObjectField(key: $0.key, value: semanticValue($0.value)) })
        default: return value
        }
    }

    static func terminalDifferences(_ actual: TerminalSnapshot, from expected: TerminalSnapshot) -> [String] {
        var differences: [String] = []
        if actual.root != expected.root { differences.append("terminal root/content/props differ from batch") }
        let keys = Set(actual.state.keys).union(expected.state.keys)
        let changed = keys.filter { actual.state[$0] != expected.state[$0] }.map(\.displayString).sorted()
        if !changed.isEmpty { differences.append("terminal state/defaults differ from batch: " + changed.joined(separator: ", ")) }
        if actual.complete != expected.complete || actual.interrupted != expected.interrupted {
            differences.append("terminal completion/interruption differs from batch")
        }
        if actual.meta?.incomplete != expected.meta?.incomplete
            || actual.meta?.unresolved.sorted() != expected.meta?.unresolved.sorted()
            || actual.meta?.orphaned.sorted() != expected.meta?.orphaned.sorted()
            || actual.meta?.statementCount != expected.meta?.statementCount {
            differences.append("terminal parse completeness/references/statements differ from batch")
        }
        return differences
    }

    @MainActor private static func check(_ state: OpenUIState, meta: ParseMeta?, label: String, failures: inout [String]) {
        if state.root == nil { failures.append(label + ": missing root") }
        if !state.isComplete { failures.append(label + ": incomplete document") }
        if state.isInterrupted { failures.append(label + ": unexpectedly interrupted document") }
        if meta == nil { failures.append(label + ": missing parse result") }
        if meta?.incomplete == true { failures.append(label + ": incomplete parse after completion") }
        if let unresolved = meta?.unresolved, !unresolved.isEmpty {
            failures.append(label + ": unresolved references: " + unresolved.joined(separator: ", "))
        }
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
