#if os(macOS)
import AppKit
import ApplicationServices
import SwiftIntelligentUI
import SwiftLang
import SwiftUI
import WebKit
import XCTest
@testable import OpenUIGallery

/// Native rendering evidence for complete, checked-in programs. These are Mac
/// renders at phone-like widths, not iPhone captures or visual-quality scores.
final class GalleryEditorialRenderingTests: XCTestCase {
    @MainActor private static let application: NSApplication = {
        let application = NSApplication.shared
        application.finishLaunching()
        return application
    }()

    @MainActor func testCompleteEditorialScenesRenderAtNarrowAndRegularWidths() async throws {
        let resourceRoot = try GalleryResources.root()
        let catalog = try GalleryCatalog(resourceRoot: resourceRoot)
        let resources = OpenUIResourceContext(loader: try SnapshotImageLoader(resourceRoot: resourceRoot))
        let sections = [
            "heat-pump": ["核心概览", "空调是怎么搬运热量的", "空调制冷和制热有什么区别",
                          "一句话总结", "把室外本来就存在的热量搬进屋里"],
            "code-isolation": ["服务端执行用户代码", "四种常见隔离技术怎么选", "服务端执行架构怎么设计",
                               "如果已经使用 Kubernetes", "按现有条件选型", "参考资料"]
        ]
        for kind in GalleryLibrary.allCases {
            for id in ["heat-pump", "code-isolation"] {
                let entry = try XCTUnwrap(catalog.entries.first { $0.section == .cases && $0.item.id == id })
                let source = try entry.source(for: kind)
                let requiredText = try XCTUnwrap(sections[id])
                for width in [CGFloat(320), 390] {
                    for scheme in [ColorScheme.light, .dark] {
                        try await render(source, kind: kind, name: id, width: width, scheme: scheme,
                                         requiredText: requiredText, resources: resources)
                    }
                }
                if id == "heat-pump" {
                    try await render(source, kind: kind, name: id, width: 390, scheme: .light,
                                     typeSize: .accessibility3, requiredText: requiredText, resources: resources)
                }
            }
        }
    }

    @MainActor func testExistingPhotoRowRendersWithItsExactBundledImage() async throws {
        let resourceRoot = try GalleryResources.root()
        let row = try XCTUnwrap(try GalleryComponent.load(.openIntelligentUI, resourceRoot: resourceRoot)
            .first { $0.name == "Row" })
        let example = try XCTUnwrap(row.examples.first { $0.id == "image-reading" })
        let loader = try SnapshotImageLoader(resourceRoot: resourceRoot, allowedSources: [GalleryImageLoader.cameraURL])
        let request = try XCTUnwrap(loader.request(for: GalleryImageLoader.cameraURL, relativeTo: nil))
        let imageData = try await loader.data(for: request)
        XCTAssertEqual(imageData, try Data(contentsOf: resourceRoot.appendingPathComponent("Images/nikon-front.jpg")))
        let unbundled = try XCTUnwrap(loader.request(for: "https://example.com/unbundled.jpg", relativeTo: nil))
        do { _ = try await loader.data(for: unbundled); XCTFail("Snapshot resources must never fall through to the network") }
        catch { XCTAssertTrue(error is GalleryFailure) }
        let image = try XCTUnwrap(NSImage(data: imageData))
        // The existing exact-source override removes asynchronous decoding from
        // this composition check; the Gallery loader has its own transport test.
        let images = [GalleryImageLoader.cameraURL: Image(nsImage: image)]
        for width in [CGFloat(320), 390] {
            for scheme in [ColorScheme.light, .dark] {
                try await render(example.program, kind: .openIntelligentUI, name: "photo-row", width: width, scheme: scheme,
                                 requiredText: ["旅行摄影", "检查相机和存储卡", "Wolfgang Moroder"],
                                 resources: OpenUIResourceContext(loader: loader), images: images)
            }
        }
    }

    @MainActor private func render(_ source: String, kind: GalleryLibrary, name: String, width: CGFloat, scheme: ColorScheme,
                                   typeSize: DynamicTypeSize = .large, requiredText: [String], resources: OpenUIResourceContext,
                                   images: [String: Image] = [:]) async throws {
        _ = Self.application
        let session = try GalleryDocumentSession(kind: kind, source: source, title: name)
        defer { session.retire() }
        XCTAssertTrue(session.state.errors.isEmpty, session.state.errors.map(\.message).joined(separator: "; "))
        XCTAssertTrue(session.state.isComplete)
        let root = try XCTUnwrap(session.state.root)
        let revision = session.state.sourceRevision
        let components = elements(in: .element(root))
        // These fixtures require no remote visual resources. Fail before mount
        // if an edit introduces one rather than silently exercising the network.
        for element in components {
            if ["SearchImage", "YouTube", "Map", "HtmlView"].contains(element.typeName) {
                throw GalleryFailure("Snapshot fixture requires a remote renderer: \(element.typeName)")
            }
            if element.typeName == "Image" {
                guard case .string(let source) = element.props.first(where: { $0.0 == "src" })?.1,
                      images[source.displayString] != nil else {
                    throw GalleryFailure("Snapshot fixture Image needs an exact bundled override")
                }
            }
            if ["Svg", "SVG"].contains(element.typeName),
               case .string(let source) = element.props.first(where: { $0.0 == "src" })?.1,
               !source.displayString.isEmpty {
                throw GalleryFailure("Snapshot fixture SVG must keep its inline content")
            }
        }
        let svgCount = components.filter { ["Svg", "SVG"].contains($0.typeName) }.count
        // Match Gallery's document padding, but measure the entire natural
        // height without a viewport crop or a replacement miniature program.
        let content = OpenUIView(state: session.state, library: session.library)
            .openUIResourceContext(resources)
            .openIntelligentUIImages(images)
            .dynamicTypeSize(typeSize)
            .environment(\.horizontalSizeClass, .compact)
            .environment(\.verticalSizeClass, .regular)
            .environment(\.locale, Locale(identifier: "zh-Hans"))
            .environment(\.layoutDirection, .leftToRight)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(width: width, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme)
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: width, height: 844),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        do {
            try await activateAccessibility(in: host)
            let size = try await settledSize(host, window: window, width: width, svgCount: svgCount, requiredText: requiredText)
            host.displayIfNeeded()
            let bitmap = try await mountedBitmap(host)
            try saveEvidence(bitmap, source: source, kind: kind, name: name, size: size, scheme: scheme,
                             typeSize: typeSize, renderedText: renderedText(in: host), requiredText: requiredText)
            XCTAssertEqual(size.width, width, accuracy: 0.5)
            XCTAssertGreaterThan(size.height, 100)
            XCTAssertGreaterThan(bitmap.pixelsWide, 0)
            XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
            XCTAssertTrue(hasContent(bitmap), "The full-document bitmap must contain more than its background")
            XCTAssertEqual(session.draft, source)
            XCTAssertEqual(session.state.sourceRevision, revision, "Rendering must not resubmit the program")
            XCTAssertTrue(session.state.errors.isEmpty, session.state.errors.map(\.message).joined(separator: "; "))
            for web in descendants(of: host).compactMap({ $0 as? WKWebView }) {
                let frame = web.convert(web.bounds, to: host)
                XCTAssertGreaterThan(frame.width, 0)
                XCTAssertGreaterThan(frame.height, 0)
                XCTAssertGreaterThanOrEqual(frame.minX, -0.5, "The mounted diagram must fit the document width")
                XCTAssertLessThanOrEqual(frame.maxX, host.bounds.width + 0.5)
                XCTAssertGreaterThanOrEqual(frame.minY, -0.5)
                XCTAssertLessThanOrEqual(frame.maxY, host.bounds.height + 0.5)
            }
        } catch {
            host.displayIfNeeded()
            let bitmap = (try? await mountedBitmap(host)) ?? (try? nativeBitmap(host))
            try saveEvidence(bitmap, source: source, kind: kind, name: name, size: host.bounds.size, scheme: scheme,
                             typeSize: typeSize, renderedText: renderedText(in: host), requiredText: requiredText,
                             failure: String(describing: error))
            throw GalleryFailure("\(kind.rawValue)/\(name)/\(Int(width))/\(scheme)/\(typeSize): \(error)")
        }
    }

    @MainActor private func settledSize<Content: View>(_ host: NSHostingView<Content>, window: NSWindow,
                                                      width: CGFloat, svgCount: Int, requiredText: [String]) async throws -> CGSize {
        let deadline = Date().addingTimeInterval(8)
        var previous: CGSize?
        var stableSince: Date?
        repeat {
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            guard size.width.isFinite, size.height.isFinite, size.height > 0, size.height < 30_000 else {
                throw GalleryFailure("Invalid full-document fitting size: \(size)")
            }
            let fullSize = CGSize(width: width, height: ceil(size.height))
            if host.frame.size != fullSize {
                window.setContentSize(fullSize)
                host.setFrameSize(fullSize)
                host.layoutSubtreeIfNeeded()
            }
            let webViews = descendants(of: host).compactMap { $0 as? WKWebView }
            var mediaReady = webViews.count == svgCount
            for web in webViews {
                if web.isLoading { mediaReady = false; continue }
                let ready = try? await web.evaluateJavaScript(
                    "document.readyState === 'complete' && document.querySelector('svg') !== null",
                    in: nil, contentWorld: .defaultClient)
                if ready as? Bool != true { mediaReady = false }
            }
            let text = renderedText(in: host)
            let textReady = requiredText.allSatisfy { text.contains($0) }
            if abs(size.width - width) <= 0.5, mediaReady, textReady {
                if let previous, abs(previous.height - size.height) <= 0.5 {
                    if let stableSince, Date().timeIntervalSince(stableSince) >= 0.25 { return fullSize }
                } else { stableSince = Date() }
                previous = size
            } else { previous = nil; stableSince = nil }
            try await Task.sleep(nanoseconds: 50_000_000)
        } while Date() < deadline
        let missing = requiredText.filter { !renderedText(in: host).contains($0) }
        throw GalleryFailure("Full-document layout, text or local SVG loading did not settle: \(host.fittingSize); missing text: \(missing)")
    }

    private func elements(in value: Value) -> [EvaluatedElement] {
        switch value {
        case .element(let element): return [element] + element.props.flatMap { elements(in: $0.1) }
        case .array(let values): return values.flatMap { elements(in: $0) }
        case .object(let fields): return fields.flatMap { elements(in: $0.value) }
        default: return []
        }
    }

    @MainActor private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    @MainActor private func activateAccessibility(in host: NSView) async throws {
        host.layoutSubtreeIfNeeded()
        // Use the same native observation barrier as the SDK's mounted-text
        // tests. SwiftUI builds virtual accessibility nodes lazily.
        let request = await Task.detached {
            let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            var role: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(application, kAXRoleAttribute as CFString, &role)
            return (code: error.rawValue, role: role as? String)
        }.value
        guard request.code == AXError.success.rawValue, request.role == kAXApplicationRole as String else {
            throw GalleryFailure("Could not observe the mounted accessibility tree: \(request)")
        }
    }

    @MainActor private func renderedText(in root: NSView) -> String {
        var visited = Set<ObjectIdentifier>(), retained: [NSObject] = [], text: [String] = []
        func attribute(_ name: String, on object: NSObject) -> AnyObject? {
            let selector = NSSelectorFromString(name)
            return object.responds(to: selector) ? object.perform(selector)?.takeUnretainedValue() : nil
        }
        func visit(_ object: NSObject, depth: Int) {
            guard depth < 128, visited.count < 8_192,
                  visited.insert(ObjectIdentifier(object)).inserted else { return }
            retained.append(object)
            for name in ["accessibilityLabel", "accessibilityValue"] {
                let value = attribute(name, on: object)
                if let string = value as? NSAttributedString { text.append(string.string) }
                else if let string = value as? String { text.append(string) }
            }
            for child in attribute("accessibilityChildren", on: object) as? [Any] ?? [] {
                if let child = child as? NSObject { visit(child, depth: depth + 1) }
            }
            if let view = object as? NSView {
                for child in view.subviews { visit(child, depth: depth + 1) }
            }
        }
        visit(root, depth: 0)
        return withExtendedLifetime(retained) { text.joined(separator: "\n") }
    }

    @MainActor private func saveEvidence(_ bitmap: NSBitmapImageRep?, source: String, kind: GalleryLibrary, name: String,
                              size: CGSize, scheme: ColorScheme, typeSize: DynamicTypeSize,
                              renderedText: String, requiredText: [String], failure: String? = nil) throws {
        let path = ProcessInfo.processInfo.environment["OPENUI_SNAPSHOT_DIR"].flatMap { $0.isEmpty ? nil : $0 }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("outputs/verification/visual").path
        let directory = URL(fileURLWithPath: path).appendingPathComponent("gallery-editorial", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let mode = scheme == .dark ? "dark" : "light"
        let type = typeSize.isAccessibilitySize ? "accessibility3" : "large"
        let program = kind.rawValue + "-" + name
        let stem = "\(program)-\(Int(size.width))-\(mode)-\(type)-macos"
        if let bitmap {
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: directory.appendingPathComponent(stem + ".png"))
        }
        try source.write(to: directory.appendingPathComponent(program + ".openui"), atomically: true, encoding: .utf8)
        try renderedText.write(to: directory.appendingPathComponent(stem + ".txt"), atomically: true, encoding: .utf8)
        var metadata: [String: Any] = [
            "library": kind.rawValue, "program": program + ".openui", "image": stem + ".png", "platform": "macOS",
            "widthPoints": Double(size.width), "fullHeightPoints": Double(size.height),
            "pixelsWide": bitmap?.pixelsWide ?? 0, "pixelsHigh": bitmap?.pixelsHigh ?? 0,
            "colorScheme": mode, "dynamicTypeSize": type, "locale": "zh-Hans",
            "requiredText": requiredText, "observedText": stem + ".txt", "status": failure == nil ? "captured" : "failed",
            "capture": "NSHostingView with native WKWebView snapshots at their mounted rectangles.",
            "coverage": "Entire initially visible document at its natural height; disclosures retain their default state.",
            "review": "Rendering and geometry evidence only; no visual-quality score or iPhone rendering claim."
        ]
        if let failure { metadata["failure"] = failure }
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent(stem + ".json"))
    }

    @MainActor private func nativeBitmap<Content: View>(_ host: NSHostingView<Content>) throws -> NSBitmapImageRep {
        guard host.bounds.width.isFinite, host.bounds.height.isFinite,
              host.bounds.width > 0, host.bounds.height > 0, host.bounds.height < 30_000 else {
            throw GalleryFailure("Cannot capture an invalid document rectangle: \(host.bounds)")
        }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    @MainActor private func mountedBitmap<Content: View>(_ host: NSHostingView<Content>) async throws -> NSBitmapImageRep {
        let bitmap = try nativeBitmap(host)
        let webViews = descendants(of: host).compactMap { $0 as? WKWebView }
        guard !webViews.isEmpty else { return bitmap }
        // WebKit owns a separate compositing surface that cacheDisplay can omit.
        // Capture that actual surface, preserving its measured position/size in
        // the mounted document rather than substituting an SVG implementation.
        let canvas = try XCTUnwrap(CGContext(data: nil, width: bitmap.pixelsWide, height: bitmap.pixelsHigh,
                                            bitsPerComponent: 8, bytesPerRow: bitmap.pixelsWide * 4,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        canvas.draw(try XCTUnwrap(bitmap.cgImage), in: CGRect(x: 0, y: 0, width: CGFloat(bitmap.pixelsWide), height: CGFloat(bitmap.pixelsHigh)))
        let scaleX = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / host.bounds.height
        for web in webViews {
            let configuration = WKSnapshotConfiguration()
            configuration.rect = web.bounds
            let image = try await web.takeSnapshot(configuration: configuration)
            let native = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            XCTAssertTrue(hasContent(NSBitmapImageRep(cgImage: native)), "The local SVG snapshot must contain its drawing")
            let frame = web.convert(web.bounds, to: host)
            let y = host.isFlipped ? host.bounds.height - frame.maxY : frame.minY
            canvas.draw(native, in: CGRect(x: frame.minX * scaleX, y: y * scaleY,
                                           width: frame.width * scaleX, height: frame.height * scaleY))
        }
        return NSBitmapImageRep(cgImage: try XCTUnwrap(canvas.makeImage()))
    }

    private func hasContent(_ bitmap: NSBitmapImageRep) -> Bool {
        guard let background = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB) else { return false }
        var differing = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: max(1, bitmap.pixelsHigh / 256)) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: max(1, bitmap.pixelsWide / 64)) {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let difference = abs(pixel.redComponent - background.redComponent)
                    + abs(pixel.greenComponent - background.greenComponent)
                    + abs(pixel.blueComponent - background.blueComponent)
                if difference > 0.25 { differing += 1 }
            }
        }
        return differing > 16
    }
}

/// Restrict the existing exact-source Gallery loader to this capture's bundled
/// sources. Unknown URLs fail locally instead of making a network request.
private final class SnapshotImageLoader: OpenUIResourceLoading {
    private let loader: GalleryImageLoader
    private let allowedSources: Set<String>
    var resourceLimits: OpenUIResourceLimits { loader.resourceLimits }
    var authorizationScopeID: String { "gallery-snapshot-local" }

    init(resourceRoot: URL, allowedSources: Set<String> = []) throws {
        loader = try GalleryImageLoader(resourceRoot: resourceRoot)
        self.allowedSources = allowedSources
    }

    func request(for source: String, relativeTo baseURL: URL?) -> URLRequest? {
        loader.request(for: source, relativeTo: baseURL)
    }

    func data(for request: URLRequest) async throws -> Data {
        guard let source = request.url?.absoluteString, allowedSources.contains(source) else {
            throw GalleryFailure("Snapshot requested an unbundled source: \(request.url?.absoluteString ?? "nil")")
        }
        return try await loader.data(for: request)
    }
}
#endif
