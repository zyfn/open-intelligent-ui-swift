#if os(iOS)
import CoreGraphics
import SwiftUI
import UIKit
import XCTest
import SwiftLang
@testable import SwiftIntelligentUI

final class IOSProductCardRenderingTests: XCTestCase {
    @MainActor func testMountedProductMediaUsesItsDeclaredLayoutAtPhoneWidth() async throws {
        let image = try markerImage(red: 1, green: 0, blue: 0)
        for layout in ["vertical", "horizontal", "compact"] {
            let host = try ProductCardHost(source: """
            root = Col([ProductCard({id:"camera",title:"Camera",images:[{url:"marker-red",alt:"Product front"}],price:408,currency:"USD"}, "\(layout)")])
            """, images: ["marker-red": image])
            defer { host.close() }
            try await host.waitForLabels(["Camera", "Product front"])

            // Observe pixels from the actual mounted SourceImage. A square
            // source cannot manufacture the card's intended framing for us.
            let rendered = try host.capture(name: "product-\(layout)-large")
            let media = try XCTUnwrap(markerBounds(rendered, channel: 0))
            XCTAssertGreaterThan(media.width, 60, "\(layout) must paint the supplied image")
            XCTAssertEqual(media.width / media.height, layout == "vertical" ? 1.5 : 1,
                           accuracy: 0.03, "The existing \(layout) media contract must survive UIKit hosting")
            if layout == "vertical" {
                XCTAssertEqual(media.width, 320, accuracy: 2)
            } else {
                XCTAssertLessThan(media.width, 160, "A phone row must leave a readable information column")
            }
            let imageFrame = try host.frame(label: "Product front", button: true)
            let titleFrame = try host.frame(label: "Camera")
            if layout == "vertical" {
                XCTAssertGreaterThanOrEqual(titleFrame.minY, imageFrame.maxY - 1)
            } else {
                XCTAssertGreaterThanOrEqual(titleFrame.minX, imageFrame.maxX - 1)
            }
        }
    }

    @MainActor func testMountedLongProductCopyReflowsWithinNarrowAccessibilityLayout() async throws {
        let title = "Travel camera with a weather sealed body and a versatile lens for everyday photographs"
        let specification = "Includes the camera, lens, battery and charger. The full supplied specification stays visible."
        let conditions = "Returns within 30 days · Ships in 2 days"
        let image = try markerImage(red: 1, green: 0, blue: 0)
        for layout in ["horizontal", "compact"] {
            let source = """
            root = Col([ProductCard({id:"camera",title:"\(title)",images:[{url:"marker-red",alt:"Product front"}],specification:"\(specification)",condition:"Returns within 30 days",availability:"Ships in 2 days",price:408,currency:"USD",priceNote:"Tax included",purchaseURL:"https://example.com/camera",actionLabel:"View offer"}, "\(layout)")])
            """
            let ordinary = try ProductCardHost(source: source, images: ["marker-red": image])
            defer { ordinary.close() }
            try await ordinary.waitForLabels([title, specification, conditions, "View offer"])
            let ordinaryTitleHeight = try ordinary.frame(label: title).height
            ordinary.close()

            let host = try ProductCardHost(source: source, images: ["marker-red": image], typeSize: .accessibility2)
            defer { host.close() }
            try await host.waitForLabels([title, specification, conditions, "Tax included", "View offer"])
            let rendered = try host.capture(name: "product-\(layout)-accessibility2")
            let mediaPixels = try XCTUnwrap(markerBounds(rendered, channel: 0))
            XCTAssertEqual(mediaPixels.width / mediaPixels.height, 1.5, accuracy: 0.03,
                           "\(layout) must reflow to the existing vertical media treatment at accessibility sizes")

            let media = try host.frame(label: "Product front", button: true)
            let heading = try host.frame(label: title)
            let details = try host.frame(label: specification)
            let terms = try host.frame(label: conditions)
            let action = try host.frame(label: "View offer", button: true)
            XCTAssertGreaterThan(heading.height, ordinaryTitleHeight,
                                 "The long heading must gain real laid-out height with Dynamic Type")
            XCTAssertGreaterThanOrEqual(heading.minY, media.maxY - 1)
            XCTAssertGreaterThanOrEqual(details.minY, heading.maxY - 1)
            XCTAssertGreaterThanOrEqual(terms.minY, details.maxY - 1)
            XCTAssertGreaterThanOrEqual(action.minY, terms.maxY - 1)
            for label in [title, specification, conditions, "Tax included", "View offer"] {
                let frame = try host.frame(label: label)
                XCTAssertGreaterThan(frame.height, 0, label)
                XCTAssertGreaterThanOrEqual(frame.minX, -1, label)
                XCTAssertLessThanOrEqual(frame.maxX, host.controller.view.bounds.width + 1, label)
                XCTAssertGreaterThanOrEqual(frame.minY, 0, label)
                XCTAssertLessThanOrEqual(frame.maxY, host.controller.view.bounds.height + 1, label)
            }
        }
    }

    @MainActor func testMountedAlbumSelectionSurvivesDataUpdateAndPurchaseDispatchesExactURL() async throws {
        let destination = "https://example.com/offer?variant=alpha%2Fbeta&opaque=A%3DB#details"
        let source = """
        root = Col([ProductCard({id:"camera",title:$title,images:[{url:"marker-red",alt:"Product front"},{url:"marker-blue",alt:"Product rear"}],price:408,currency:"USD",purchaseURL:"\(destination)",actionLabel:"View offer"})])
        $title = "Camera"
        """
        let host = try ProductCardHost(source: source, images: [
            "marker-red": try markerImage(red: 1, green: 0, blue: 0),
            "marker-blue": try markerImage(red: 0, green: 0, blue: 1),
        ])
        defer { host.close() }
        var events: [ActionEvent] = []
        host.state.onAction = { events.append($0) }
        try await host.waitForLabels(["Camera", "Product front", "Next product image", "View offer"])
        let sourceRevision = host.state.sourceRevision
        let presentationRevision = host.state.presentationRevision
        let firstImage = try host.capture(name: "product-album-front")
        let firstBounds = try XCTUnwrap(markerBounds(firstImage, channel: 0))
        let next = try host.element(label: "Next product image", button: true)
        XCTAssertFalse(next.accessibilityTraits.contains(.notEnabled))
        XCTAssertTrue(next.accessibilityActivate(), "Activate the mounted SwiftUI button through its native accessibility action")
        try await host.waitForLabels(["Product rear"])

        let secondImage = try host.capture(name: "product-album-rear")
        let secondBounds = try XCTUnwrap(markerBounds(secondImage, channel: 2))
        XCTAssertNil(markerBounds(secondImage, channel: 0), "The first photo must actually leave the rendered media area")
        assertSameBounds(firstBounds, secondBounds)
        XCTAssertTrue(try host.element(label: "Next product image", button: true)
            .accessibilityTraits.contains(.notEnabled), "The last image disables forward navigation")

        host.state.setState("$title", value: .string("Updated camera"))
        try await host.waitForLabels(["Updated camera", "Product rear", "View offer"])
        let updated = try host.capture(name: "product-album-updated")
        assertSameBounds(secondBounds, try XCTUnwrap(markerBounds(updated, channel: 2)))
        XCTAssertNil(markerBounds(updated, channel: 0), "Updating product copy must not reset the selected photograph")
        XCTAssertEqual(host.state.sourceRevision, sourceRevision)
        XCTAssertEqual(host.state.presentationRevision, presentationRevision,
                       "Local gallery selection and a reactive field update must retain the mounted document")
        XCTAssertTrue(events.isEmpty, "Image navigation must not dispatch a purchase or another host action")

        let purchase = try host.element(label: "View offer", button: true)
        XCTAssertTrue(purchase.accessibilityActivate())
        try await host.waitUntil("purchase action reaches the host") { !events.isEmpty }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.map(\.type), ["open_url"])
        XCTAssertEqual(events.first?.params.first(where: { $0.0 == "url" })?.1, .string(OpenUIString(destination)))
        XCTAssertTrue(host.state.errors.isEmpty, "\(host.state.errors)")
    }

    private func assertSameBounds(_ lhs: CGRect, _ rhs: CGRect,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.minX, rhs.minX, accuracy: 1, file: file, line: line)
        XCTAssertEqual(lhs.minY, rhs.minY, accuracy: 1, file: file, line: line)
        XCTAssertEqual(lhs.width, rhs.width, accuracy: 1, file: file, line: line)
        XCTAssertEqual(lhs.height, rhs.height, accuracy: 1, file: file, line: line)
    }

    @MainActor private func markerImage(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> Image {
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        return Image(decorative: try XCTUnwrap(bitmap.makeImage()), scale: 1)
    }

    private func markerBounds(_ image: CGImage, channel: Int) -> CGRect? {
        guard let bitmap = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
            let bytes = bitmap.data else { return nil }
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = bytes.assumingMemoryBound(to: UInt8.self)
        var bounds = CGRect.null
        let others = [0, 1, 2].filter { $0 != channel }
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = y * bitmap.bytesPerRow + x * 4
                if pixels[offset + channel] > 200 && others.allSatisfy({ pixels[offset + $0] < 60 }) {
                    bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        return bounds.isNull ? nil : bounds
    }
}

/// Kept in this target: the mounted hierarchy, native AX actions and software
/// pixels are the observations; no replacement ProductCard renderer is used.
@MainActor private final class ProductCardHost {
    let state: OpenUIState
    let controller: UIHostingController<AnyView>
    let window: UIWindow
    private weak var previousKeyWindow: UIWindow?
    private var closed = false

    init(source: String, images: [String: Image], typeSize: DynamicTypeSize = .large) throws {
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        state.setSource(source)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        XCTAssertEqual(library.validationIssues(in: try XCTUnwrap(state.root)), [])
        self.state = state
        previousKeyWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let content = OpenIntelligentUIContentView(state: state, library: library)
            .openIntelligentUIImages(images)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, typeSize)
            .environment(\.accessibilityReduceMotion, true)
            .frame(width: 320).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white).ignoresSafeArea()
        controller = UIHostingController(rootView: AnyView(content))
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 1800))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        layout()
    }

    func close() {
        guard !closed else { return }
        closed = true
        window.isHidden = true
        window.rootViewController = nil
        state.reset()
        previousKeyWindow?.makeKey()
    }

    private func layout() {
        window.layoutIfNeeded()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    }

    private func elements() -> [NSObject] {
        var result: [NSObject] = []
        var visited = Set<ObjectIdentifier>()
        func visit(_ value: NSObject) {
            guard visited.insert(ObjectIdentifier(value)).inserted else { return }
            result.append(value)
            let count = value.accessibilityElementCount()
            if count > 0 && count != NSNotFound {
                for index in 0..<count {
                    if let child = value.accessibilityElement(at: index) as? NSObject { visit(child) }
                }
            }
            if let view = value as? UIView { view.subviews.forEach(visit) }
        }
        visit(window)
        return result
    }

    func element(label: String, button: Bool = false,
        file: StaticString = #filePath, line: UInt = #line) throws -> NSObject {
        try XCTUnwrap(elements().first {
            $0.accessibilityLabel == label && !$0.accessibilityFrame.isEmpty
                && (!button || $0.accessibilityTraits.contains(.button))
        }, "Mounted accessibility element: \(label). Labels: \(elements().compactMap(\.accessibilityLabel))",
        file: file, line: line)
    }

    func frame(label: String, button: Bool = false) throws -> CGRect {
        let screen = try element(label: label, button: button).accessibilityFrame
        return controller.view.convert(window.convert(screen, from: nil as UIWindow?), from: window)
    }

    func waitForLabels(_ labels: [String]) async throws {
        try await waitUntil("mounted product labels: \(labels)") {
            let current = Set(self.elements().filter { !$0.accessibilityFrame.isEmpty }.compactMap(\.accessibilityLabel))
            return labels.allSatisfy(current.contains)
        }
    }

    func waitUntil(_ message: String, timeout: TimeInterval = 5,
        file: StaticString = #filePath, line: UInt = #line, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            layout()
            if condition() { await Task.yield(); layout(); return }
            try await Task.sleep(nanoseconds: 10_000_000)
        } while Date() < deadline
        _ = try? capture(name: "product-observation-failure")
        XCTFail("Timed out: \(message). Labels: \(elements().compactMap(\.accessibilityLabel))", file: file, line: line)
        throw ObservationFailure.timeout
    }

    func capture(name: String) throws -> CGImage {
        layout()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let snapshot = UIGraphicsImageRenderer(bounds: controller.view.bounds, format: format).image { context in
            UIColor.white.setFill()
            context.fill(controller.view.bounds)
            // Framework XCTest has no app render server. This captures the
            // existing UIKit-hosted layers, including SwiftUI's text and image.
            controller.view.layer.render(in: context.cgContext)
        }
        if let output = ProcessInfo.processInfo.environment["OPENUI_SNAPSHOT_DIR"], !output.isEmpty {
            let directory = URL(fileURLWithPath: output).appendingPathComponent("ios-native", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try XCTUnwrap(snapshot.pngData()).write(to: directory.appendingPathComponent(name + ".png"))
        }
        return try XCTUnwrap(snapshot.cgImage)
    }

    private enum ObservationFailure: Error { case timeout }
}
#endif
