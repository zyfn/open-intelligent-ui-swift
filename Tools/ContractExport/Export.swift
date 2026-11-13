import Foundation
import OpenUILang
import OpenUISwiftUI
import SwiftIntelligentUI

@main enum ContractExport {
    @MainActor static func main() async throws {
        var args = Array(CommandLine.arguments.dropFirst())
        let exportReader = args.contains("--reader-contract")
        let includeSearch = args.contains("--include-search")
        let historical = args.contains("--historical")
        args.removeAll { ["--reader-contract", "--include-search", "--historical"].contains($0) }
        var excluded = Set<String>()
        if let index = args.firstIndex(of: "--exclude-components") {
            guard args.indices.contains(index + 1) else {
                throw NSError(domain: "ContractExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "--exclude-components requires comma-separated component names"])
            }
            excluded = Set(args[index + 1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            args.removeSubrange(index...index + 1)
        }
        // The provider is never called during contract export or validation.
        let imageSearch: IntelligentUIImageSearch? = includeSearch ? IntelligentUIImageSearch { query in
            .init(url: "https://example.invalid/contract-only.jpg", alt: query)
        } : nil
        let library = try IntelligentUILibrary(imageSearch: imageSearch, excludingComponents: excluded)
        if args.first == "--validate", args.count >= 2 {
            let text = try String(contentsOfFile: args[1], encoding: .utf8)
            let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
            let program = object?["program"] as? String ?? text
            let state = library.makeState(); state.setSource(program)
            let issues = library.validationIssues(in: state, source: program,
                                                 profile: historical ? .historical : .generation)
            let checks = await ProgramChecks.run(args.count == 4 && args[2] == "--case" ? args[3] : nil, state: state, library: library)
            let valid = issues.isEmpty && state.root != nil && checks.values.allSatisfy { $0 }
            let result: [String: Any] = ["valid": valid,
                                         "errors": issues,
                                         "checks": checks,
                                         "root": state.root?.typeName ?? ""]
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            exit(valid ? 0 : 1)
        }
        let output = URL(fileURLWithPath: args.first ?? "outputs/contracts", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        if exportReader {
            try library.readerSpecification.jsonString().write(to: output.appendingPathComponent("reader-spec.json"), atomically: true, encoding: .utf8)
            print("Exported historical reader contract to \(output.path)")
            return
        }
        try library.specificationJSON.write(to: output.appendingPathComponent("spec.json"), atomically: true, encoding: .utf8)
        try library.systemPrompt.write(to: output.appendingPathComponent("prompt.txt"), atomically: true, encoding: .utf8)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library.manifest).write(to: output.appendingPathComponent("manifest.json"))
        print("Exported \(library.specification.components.count) components, \(library.specification.functions.count) functions to \(output.path)")
    }
}
