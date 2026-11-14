import Foundation
import OpenUICore
import OpenIntelligentSwiftUI
import OpenSwiftUI

struct GalleryFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

enum GalleryLibrary: String, CaseIterable, Codable, Identifiable {
    case standard, intelligent
    var id: String { rawValue }
    var title: String { self == .standard ? "Standard UI" : "Intelligent UI" }

    func makeLibrary() throws -> OpenUILibrary {
        switch self {
        case .standard: return try .standard()
        case .intelligent:
            return try .intelligent(referenceDate: Date(timeIntervalSince1970: 1_793_491_200), imageSearch: IntelligentUIImageSearch { query in
                // This is an explicit resource-state diagnostic, not a live search.
                if query == "gallery-loading" {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                }
                guard query == "gallery-loading" || query == "gallery-camera" else {
                    throw GalleryFailure("Gallery 模拟图片搜索失败")
                }
                return .init(url: GalleryImageLoader.cameraURL, alt: "Nikon D850 来源照片")
            })
        }
    }
}

enum GallerySection: String, CaseIterable, Identifiable {
    case cases = "Cases", diagnostics = "Diagnostics"
    var id: String { rawValue }
    var title: String { self == .cases ? "核心场景" : "组件诊断" }
}

struct GalleryOrigin: Decodable, Hashable {
    let repository: String
    let revision: String
    let path: String
}

struct GalleryCase: Decodable, Hashable {
    let id: String
    let title: String
    let summary: String
    let category: String
    let tags: [String]
    let programs: [String: String]
    let origin: GalleryOrigin?
}

struct GalleryEntry: Identifiable, Hashable {
    let section: GallerySection
    let item: GalleryCase
    let directory: URL
    var id: String { section.rawValue + "/" + item.id }
    func supports(_ library: GalleryLibrary) -> Bool { item.programs[library.rawValue] != nil }

    func source(for library: GalleryLibrary) throws -> String {
        guard let relative = item.programs[library.rawValue] else {
            throw GalleryFailure("\(item.title) 没有 \(library.title) 程序；请选择支持该库的案例。")
        }
        let url = try GalleryCatalog.programURL(relative, in: directory)
        return try GalleryImportedProgram.read(url: url, library: library)
    }
}

struct GalleryCatalog {
    private struct Document: Decodable {
        let schemaVersion: Int
        let cases: [GalleryCase]
    }
    let entries: [GalleryEntry]

    init(resourceRoot: URL) throws {
        var result: [GalleryEntry] = []
        for section in GallerySection.allCases {
            let directory = resourceRoot.appendingPathComponent(section.rawValue, isDirectory: true)
            let data = try Data(contentsOf: directory.appendingPathComponent("catalog.json"))
            let items = try Self.decode(data, requiringBothLibraries: section == .cases)
            for item in items {
                let entry = GalleryEntry(section: section, item: item, directory: directory)
                for library in GalleryLibrary.allCases where entry.supports(library) {
                    _ = try entry.source(for: library)
                }
                result.append(entry)
            }
        }
        entries = result
    }

    static func decode(_ data: Data, requiringBothLibraries: Bool) throws -> [GalleryCase] {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1, !document.cases.isEmpty else {
            throw GalleryFailure("Gallery catalog 必须是非空的 schemaVersion 1。")
        }
        var ids = Set<String>()
        for item in document.cases {
            guard !item.id.isEmpty, !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  ids.insert(item.id).inserted, !item.programs.isEmpty else {
                throw GalleryFailure("Gallery catalog 存在空名称、重复 ID 或缺少程序：\(item.id)")
            }
            guard item.programs.keys.allSatisfy({ GalleryLibrary(rawValue: $0) != nil }) else {
                throw GalleryFailure("案例 \(item.id) 指定了未知组件库。")
            }
            if requiringBothLibraries && item.programs.count != GalleryLibrary.allCases.count {
                throw GalleryFailure("核心场景 \(item.id) 必须有两套独立程序。")
            }
            for path in item.programs.values { try validateRelativePath(path) }
        }
        return document.cases
    }

    private static func validateRelativePath(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard path.hasSuffix(".openui"), !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !path.contains("\\") else {
            throw GalleryFailure("案例程序必须使用目录内的 .openui 相对路径：\(path)")
        }
    }

    static func programURL(_ path: String, in directory: URL) throws -> URL {
        try validateRelativePath(path)
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let file = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(root.path + "/") else {
            throw GalleryFailure("程序路径越过案例目录：\(path)")
        }
        return file
    }
}

enum GalleryImportedProgram {
    static let maximumBytes = 1_048_576

    static func read(url: URL, library: GalleryLibrary) throws -> String {
        let text = try readRaw(url: url)
        let json = url.pathExtension.lowercased() == "json" || text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
        return try decode(text, isJSON: json, library: library)
    }

    static func readRaw(url: URL) throws -> String {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumBytes else { throw GalleryFailure("示例源码超过 1 MiB。") }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumBytes, let text = String(data: data, encoding: .utf8) else {
            throw GalleryFailure("示例必须是 1 MiB 以内的 UTF-8 文本。")
        }
        return text
    }

    static func decode(_ text: String, isJSON: Bool, library: GalleryLibrary) throws -> String {
        guard isJSON else { return text }
        guard let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let program = object["program"] as? String else {
            throw GalleryFailure("JSON 示例必须包含字符串字段 program。")
        }
        if let declared = object["library"] {
            guard let name = declared as? String, let kind = GalleryLibrary(rawValue: name), kind == library else {
                throw GalleryFailure("JSON 的 library 与当前选中的组件库不一致。")
            }
        }
        return program
    }
}
