import Foundation
import SwiftOpenUI
import SwiftIntelligentUI

@main struct GuideExport {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "GuideExport", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Usage: GuideExport /absolute/output/directory"])
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let libraries: [(id: String, library: OpenUILibrary)] = [
            ("openui", try .openUI()),
            ("intelligent-ui", try .openIntelligentUI())
        ]
        for (id, library) in libraries {
            let destination = output.appendingPathComponent(id + ".json")
            let source = library.specificationJSON
            guard let parsed = try JSONSerialization.jsonObject(with: Data(source.utf8)) as? [String: Any],
                  parsed["components"] is [String: Any] else {
                throw NSError(domain: "GuideExport", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid SDK specification: " + id])
            }
            try source.write(to: destination, atomically: true, encoding: .utf8)
            print("Exported " + id + " from the current SDK")
        }
        let metadata: [String: Any] = [
            "sourceCommit": ProcessInfo.processInfo.environment["GITHUB_SHA"] ?? "local",
            "exporter": "OpenUILibrary.specificationJSON",
            "libraries": ["openui", "intelligent-ui"]
        ]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("metadata.json"))
    }
}
