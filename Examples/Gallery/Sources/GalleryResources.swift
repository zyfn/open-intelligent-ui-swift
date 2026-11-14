import Foundation
import OpenUICore

enum GalleryResources {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }

    static func root() throws -> URL {
        guard let url = bundle.url(forResource: "Resources", withExtension: nil) else {
            throw GalleryFailure("Gallery Resources 未打包；请使用 Gallery package 或 Xcode project 构建。")
        }
        return url
    }
}

/// Both UI libraries receive the same exact-source bundle transport. A bundled
/// photograph is never substituted for another URL or another place/product.
final class GalleryImageLoader: OpenUIResourceLoading {
    static let cameraURL = "https://upload.wikimedia.org/wikipedia/commons/9/9b/Nikon_DSLR_camera_D850.jpg"
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
        if let source = request.url?.absoluteString, let url = files[source] {
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
