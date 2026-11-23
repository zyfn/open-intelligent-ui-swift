#if os(macOS)
import AppKit
import SwiftIntelligentUI
import SwiftLang
import SwiftUI
import WebKit
import XCTest
@testable import OpenUIGallery

/// Native rendering evidence for complete, checked-in programs. These are Mac
/// renders at phone-like widths, not iPhone captures or visual-quality scores.
final class GalleryEditorialRenderingTests: XCTestCase {
    @MainActor func testCompleteEditorialScenesRenderAtNarrowAndRegularWidths() async throws {
        let resourceRoot = try GalleryResources.root()
        let catalog = try GalleryCatalog(resourceRoot: resourceRoot)
        let resources = OpenUIResourceContext(loader: try GalleryImageLoader(resourceRoot: resourceRoot))
        for id in ["heat-pump", "code-isolation"] {
            let entry = try XCTUnwrap(catalog.entries.first { $0.section == .cases && $0.item.id == id })
            let source = try entry.source(for: .openIntelligentUI)
            for width in [CGFloat(320), 390] {
                for scheme in [ColorScheme.light, .dark] {
                    try await render(source, name: id, width: width, scheme: scheme, resources: resources)
                }
            }
            if id == "heat-pump" {
                try await render(source, name: id, width: 390, scheme: .light,
                                 typeSize: .accessibility3, resources: resources)
            }
        }
    }

    @MainActor func testExistingPhotoRowRendersWithItsExactBundledImage() async throws {
        let resourceRoot = try GalleryResources.root()
        let row = try XCTUnwrap(try GalleryComponent.load(.openIntelligentUI, resourceRoot: resourceRoot)
            .first { $0.name == "Row" })
        let example = try XCTUnwrap(row.examples.first { $0.id == "image-reading" })
        let loader = try GalleryImageLoader(resourceRoot: resourceRoot)
        let request = try XCTUnwrap(loader.request(for: GalleryImageLoader.cameraURL, relativeTo: nil))
        let imageData = try await loader.data(for: request)
        let image = try XCTUnwrap(NSImage(data: imageData))
        // The existing exact-source override removes asynchronous decoding from
        // this composition check; the Gallery loader has its own transport test.
        let images = [GalleryImageLoader.cameraURL: Image(nsImage: image)]
        for width in [CGFloat(320), 390] {
            for scheme in [ColorScheme.light, .dark] {
                try await render(example.program, name: "photo-row", width: width, scheme: scheme,
                                 resources: OpenUIResourceContext(loader: loader), images: images)
            }
        }
    }

    @MainActor private func render(_ source: String, name: String, width: CGFloat, scheme: ColorScheme,
                                   typeSize: DynamicTypeSize = .large, resources: OpenUIResourceContext,
                                   images: [String: Image] = [:]) async throws {
        _ = NSApplication.shared
        let session = try GalleryDocumentSession(kind: .openIntelligentUI, source: source, title: name)
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
        }
        let svgCount = components.filter { $0.typeName == "Svg" }.count
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
        let size = try await settledSize(host, window: window, width: width, svgCount: svgCount)
        XCTAssertEqual(size.width, width, accuracy: 0.5)
        XCTAssertGreaterThan(size.height, 100)
        host.displayIfNeeded()
        let bitmap = try await mountedBitmap(host)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
        XCTAssertTrue(hasContent(bitmap), "The full-document bitmap must contain more than its background")
        XCTAssertEqual(session.draft, source)
        XCTAssertEqual(session.state.sourceRevision, revision, "Rendering must not resubmit the program")
        XCTAssertTrue(session.state.errors.isEmpty, session.state.errors.map(\.message).joined(separator: "; "))

        if let path = ProcessInfo.processInfo.environment["OPENUI_SNAPSHOT_DIR"], !path.isEmpty {
            let directory = URL(fileURLWithPath: path).appendingPathComponent("gallery-editorial", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let mode = scheme == .dark ? "dark" : "light"
            let type = typeSize.isAccessibilitySize ? "accessibility3" : "large"
            let stem = "\(name)-\(Int(width))-\(mode)-\(type)-macos"
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: directory.appendingPathComponent(stem + ".png"))
            try source.write(to: directory.appendingPathComponent(name + ".openui"), atomically: true, encoding: .utf8)
            let metadata: [String: Any] = [
                "program": name + ".openui", "image": stem + ".png", "platform": "macOS",
                "widthPoints": Double(size.width), "fullHeightPoints": Double(size.height),
                "pixelsWide": bitmap.pixelsWide, "pixelsHigh": bitmap.pixelsHigh,
                "colorScheme": mode, "dynamicTypeSize": type, "locale": "zh-Hans",
                "capture": "NSHostingView with native WKWebView snapshots at their mounted rectangles.",
                "coverage": "Entire initially visible document at its natural height; disclosures retain their default state.",
                "review": "Rendering and geometry evidence only; no visual-quality score or iPhone rendering claim."
            ]
            try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent(stem + ".json"))
        }
    }

    @MainActor private func settledSize<Content: View>(_ host: NSHostingView<Content>, window: NSWindow,
                                                      width: CGFloat, svgCount: Int) async throws -> CGSize {
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
            if abs(size.width - width) <= 0.5, mediaReady {
                if let previous, abs(previous.height - size.height) <= 0.5 {
                    if let stableSince, Date().timeIntervalSince(stableSince) >= 0.25 { return fullSize }
                } else { stableSince = Date() }
                previous = size
            } else { previous = nil; stableSince = nil }
            try await Task.sleep(nanoseconds: 50_000_000)
        } while Date() < deadline
        throw GalleryFailure("Full-document layout or local SVG loading did not settle: \(host.fittingSize)")
    }

    private func elements(in value: Value) -> [EvaluatedElement] {
        switch value {
        case .element(let element): return [element] + element.props.flatMap { elements(in: $0.1) }
        case .array(let values): return values.flatMap { elements(in: $0) }
        default: return []
        }
    }

    @MainActor private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    @MainActor private func mountedBitmap<Content: View>(_ host: NSHostingView<Content>) async throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
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
#endif
