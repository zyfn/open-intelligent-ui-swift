import Foundation
import SwiftLang

enum GalleryResources {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }

    static func root() throws -> URL {
        #if SWIFT_PACKAGE
        let url = bundle.url(forResource: "Resources", withExtension: nil)
        #else
        // Keep the iOS app's root free of the reserved Resources directory.
        let url = bundle.url(forResource: "Resources", withExtension: nil, subdirectory: "GalleryResources")
        #endif
        guard let url else {
            throw GalleryFailure("Gallery Resources 未打包；请使用 Gallery package 或 Xcode project 构建。")
        }
        return url
    }
}

struct GalleryComponentMarks {
    static let resourcePath = "Components/marks.json"
    private static let checkoutPath = "Examples/Gallery/Resources/" + resourcePath
    private var names: [String: Set<String>] = [:]

    init() {}

    init(contentsOf url: URL) throws {
        names = try JSONDecoder().decode([String: Set<String>].self, from: Data(contentsOf: url))
    }

    func contains(_ component: String, in library: GalleryLibrary) -> Bool {
        names[library.rawValue]?.contains(component) == true
    }

    static func checkout() -> URL? {
        let starts = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
            Bundle.main.bundleURL
        ]
        for start in starts {
            var directory = start.standardizedFileURL
            while directory.path != "/" {
                if FileManager.default.fileExists(atPath: directory.appendingPathComponent(checkoutPath).path) {
                    return directory
                }
                let parent = directory.deletingLastPathComponent()
                guard parent != directory else { break }
                directory = parent
            }
        }
        return nil
    }

    static func read(in repository: URL) throws -> Self {
        try withFile(in: repository) { try Self(contentsOf: $0) }
    }

    static func set(_ marked: Bool, component: String, library: GalleryLibrary, in repository: URL) throws -> Self {
        try withFile(in: repository) { url in
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var result: Result<Self, Error>?
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { file in
                result = Result {
                    var latest = try Self(contentsOf: file)
                    if latest.contains(component, in: library) == marked { return latest }
                    if marked { latest.names[library.rawValue, default: []].insert(component) }
                    else { latest.names[library.rawValue]?.remove(component) }
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    var data = try encoder.encode(latest.names.mapValues { $0.sorted() })
                    data.append(0x0A)
                    try data.write(to: file, options: .atomic)
                    return latest
                }
            }
            if let coordinationError { throw coordinationError }
            guard let result else { throw GalleryFailure("无法保存组件划线。") }
            return try result.get()
        }
    }

    private static func withFile<T>(in repository: URL, _ operation: (URL) throws -> T) throws -> T {
        let scoped = repository.startAccessingSecurityScopedResource()
        defer { if scoped { repository.stopAccessingSecurityScopedResource() } }
        let directory = repository.resolvingSymlinksInPath().standardizedFileURL
        let file = directory.appendingPathComponent(checkoutPath).resolvingSymlinksInPath()
        guard file.path.hasPrefix(directory.path + "/"), FileManager.default.fileExists(atPath: file.path) else {
            throw GalleryFailure("请选择包含 Gallery 组件标记文件的 SDK 仓库。")
        }
        return try operation(file)
    }
}

/// Both UI libraries receive the same exact-source bundle transport. A bundled
/// photograph is never substituted for another URL or another place/product.
final class GalleryImageLoader: OpenUIResourceLoading {
    static let cameraURL = "https://upload.wikimedia.org/wikipedia/commons/9/9b/Nikon_DSLR_camera_D850.jpg"
    private static let delayedCameraURL = "https://gallery.invalid/loading-camera.jpg"
    private struct Asset: Decodable { let file: String; let source: String }
    private struct Manifest: Decodable { let images: [Asset] }
    private let files: [String: URL]
    private let remote = OpenUIURLSessionResourceLoader.shared
    var resourceLimits: OpenUIResourceLimits { remote.resourceLimits }
    var authorizationScopeID: String { "gallery-bundle-v1" }

    init(resourceRoot: URL) throws {
        let directory = resourceRoot.appendingPathComponent("Images", isDirectory: true)
        let data = try Data(contentsOf: directory.appendingPathComponent("catalog.json"))
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        var files: [String: URL] = [:]
        for asset in manifest.images {
            guard !asset.file.contains("/"), !asset.file.contains("\\"),
                  asset.file.hasSuffix(".jpg"), files[asset.source] == nil else {
                throw GalleryFailure("Gallery 图片映射重复或路径无效：\(asset.file)")
            }
            let url = directory.appendingPathComponent(asset.file)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw GalleryFailure("Gallery 图片资源缺失：\(asset.file)")
            }
            files[asset.source] = url
        }
        self.files = files
    }

    func request(for source: String, relativeTo baseURL: URL?) -> URLRequest? {
        remote.request(for: source, relativeTo: baseURL)
    }

    func data(for request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        let source = request.url?.absoluteString
        let delayed = source == Self.delayedCameraURL
        if let asset = delayed ? Self.cameraURL : source, let url = files[asset] {
            if delayed { try await Task.sleep(nanoseconds: 6_000_000_000) }
            let data = try Data(contentsOf: url)
            guard data.count <= resourceLimits.maximumResponseBytes else {
                throw GalleryFailure("Gallery 图片超过资源大小限制。")
            }
            return data
        }
        if request.url?.host == "gallery.invalid" { throw GalleryFailure("Gallery 模拟图片加载失败") }
        return try await remote.data(for: request)
    }
}
