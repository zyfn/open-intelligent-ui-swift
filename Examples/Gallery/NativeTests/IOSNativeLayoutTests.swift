#if os(iOS)
@testable import SwiftLang
import SwiftUI
import UIKit
import XCTest
@testable import SwiftOpenUI

final class IOSNativeLayoutTests: XCTestCase {
    @MainActor func testCompositeCardsKeepReadableColumnsAndVisibleActionBounds() async throws {
        for (width, typeSize, columns) in [
            (CGFloat(320), DynamicTypeSize.large, 1),
            (600, .large, 2),
            (600, .accessibility2, 1),
        ] {
            let library = try OpenUIComponents.library()
            let measured = IOSLayoutObservations()
            let registry = try observing(library.registry,
                names: ["CompositeCardItem", "ImageTextLarge", "Button", "BoldText"], measured: measured)
            let state = OpenUIState(schema: library.library.toSchema())
            state.setSource(IOSNativeLayoutFixtures.compositeCards)
            XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
            let host = try IOSNativeTestHost(OpenUIContentView(state: state, registry: registry)
                .dynamicTypeSize(typeSize).frame(width: width).fixedSize(horizontal: false, vertical: true),
                width: width, height: 2400)
            defer { host.close() }
            try await host.waitUntil("the real card header, amount and action factories have mounted native probes") {
                measured.frames.count == 8 && measured.nativeViews.count == 8
            }
            let first = try XCTUnwrap(measured.frames["CompositeCardItem:a"])
            let second = try XCTUnwrap(measured.frames["CompositeCardItem:b"])
            let expectedWidth = columns == 1 ? width : (width - 12) / 2
            XCTAssertEqual(first.width, expectedWidth, accuracy: 1)
            XCTAssertEqual(second.width, expectedWidth, accuracy: 1)
            if columns == 1 {
                XCTAssertEqual(first.minX, second.minX, accuracy: 1)
                XCTAssertGreaterThanOrEqual(second.minY, first.maxY + 11)
            } else {
                XCTAssertEqual(first.minY, second.minY, accuracy: 1)
                XCTAssertEqual(second.minX - first.maxX, 12, accuracy: 1)
            }
            for (card, action) in [(first, "Book first room"), (second, "Book second room")] {
                let target = try XCTUnwrap(measured.frames["Button:" + action])
                XCTAssertGreaterThanOrEqual(target.height, 44)
                XCTAssertGreaterThan(target.width, 44)
                XCTAssertGreaterThanOrEqual(target.minX, card.minX - 1)
                XCTAssertLessThanOrEqual(target.maxX, card.maxX + 1)
                XCTAssertGreaterThanOrEqual(target.minY, card.minY)
                XCTAssertLessThanOrEqual(target.maxY, card.maxY + 1)
            }
            XCTAssertEqual(measured.created.values.sorted(), Array(repeating: 1, count: 8),
                "Measuring a row must not mount alternate copies of its content")
            try host.saveSnapshot(name: "cards-\(Int(width))-\(columns == 1 && width == 600 ? "accessibility" : "large")")
        }
    }

    @MainActor func testWrappingContentCardsFillTheIncompleteRowAtPhoneWidths() async throws {
        let cases: [(CGFloat, [CGFloat])] = [
            (320, [320, 320, 320]),
            (350, [169, 169, 350]),
            (530, [506 / 3, 506 / 3, 506 / 3]),
        ]
        for (width, expected) in cases {
            let library = try OpenUIComponents.library()
            let measured = IOSLayoutObservations()
            let registry = try observing(library.registry, names: ["Image"], measured: measured)
            let state = OpenUIState(schema: library.library.toSchema())
            state.setSource(IOSNativeLayoutFixtures.wrappingCards)
            let host = try IOSNativeTestHost(OpenUIContentView(state: state, registry: registry)
                .dynamicTypeSize(.large).frame(width: width).fixedSize(horizontal: false, vertical: true), width: width)
            defer { host.close() }
            try await host.waitUntil("all three actual image factories have mounted their probes") {
                measured.frames.count == 3 && measured.nativeViews.count == 3
            }
            for (index, key) in ["a", "b", "c"].enumerated() {
                let frame = try XCTUnwrap(measured.frames["Image:" + key])
                XCTAssertEqual(frame.width, expected[index], accuracy: 1)
                XCTAssertEqual(frame.height, expected[index] * 9 / 16, accuracy: 1)
            }
            if width == 350 {
                let a = try XCTUnwrap(measured.frames["Image:a"])
                let b = try XCTUnwrap(measured.frames["Image:b"])
                let c = try XCTUnwrap(measured.frames["Image:c"])
                XCTAssertEqual(a.minY, b.minY, accuracy: 1)
                XCTAssertEqual(b.minX - a.maxX, 12, accuracy: 1)
                XCTAssertGreaterThan(c.minY, a.maxY)
            }
            XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        }
    }

    @MainActor func testButtonsReflowWithoutReplacingTheirMountedNativeContent() async throws {
        let library = try OpenUIComponents.library()
        let measured = IOSLayoutObservations()
        let registry = try observing(library.registry, names: ["Button"], measured: measured)
        let state = OpenUIState(schema: library.library.toSchema())
        state.setSource(IOSNativeLayoutFixtures.buttons)
        let host = try IOSNativeTestHost(OpenUIContentView(state: state, registry: registry)
            .dynamicTypeSize(.large).frame(width: 320).fixedSize(horizontal: false, vertical: true), width: 320)
        defer { host.close() }
        try await host.waitUntil("the three actual button factories received the initial column policy") {
            measured.frames.count == 3 && measured.fillWidth.count == 3
                && measured.fillWidth.values.allSatisfy { $0 }
        }
        let original = measured.nativeViews.mapValues(ObjectIdentifier.init)
        for frame in measured.frames.values {
            XCTAssertEqual(frame.width, 320, accuracy: 1)
            XCTAssertGreaterThanOrEqual(frame.height, 44)
        }
        state.setState("$direction", value: .string("row"))
        try await host.waitUntil("the committed row policy reaches the existing native button probes") {
            measured.fillWidth.count == 3 && measured.fillWidth.values.allSatisfy { !$0 }
        }
        let first = try XCTUnwrap(measured.frames["Button:One"])
        let second = try XCTUnwrap(measured.frames["Button:Two"])
        let third = try XCTUnwrap(measured.frames["Button:A substantially longer third action"])
        XCTAssertEqual(first.minY, second.minY, accuracy: 1)
        XCTAssertGreaterThan(second.minX, first.maxX)
        XCTAssertGreaterThanOrEqual(third.minY, first.maxY + 11)
        XCTAssertLessThan(first.width, 160)
        XCTAssertEqual(measured.nativeViews.mapValues(ObjectIdentifier.init), original)
        XCTAssertEqual(measured.created.values.sorted(), [1, 1, 1])
        XCTAssertTrue(measured.removed.values.allSatisfy { $0 == 0 })
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        try host.saveSnapshot(name: "buttons-reflow")
    }

    @MainActor func testStackAlignmentUpdatesTheSameButtonWidth() async throws {
        let library = try OpenUIComponents.library()
        let measured = IOSLayoutObservations()
        let registry = try observing(library.registry, names: ["Button"], measured: measured)
        let state = OpenUIState(schema: library.library.toSchema())
        state.setSource(IOSNativeLayoutFixtures.stackAlignment)
        let host = try IOSNativeTestHost(OpenUIContentView(state: state, registry: registry)
            .dynamicTypeSize(.large).frame(width: 320).fixedSize(horizontal: false, vertical: true), width: 320)
        defer { host.close() }
        try await host.waitUntil("the stretched native action is mounted") {
            measured.frames["Button:One"] != nil && measured.fillWidth["Button:One"] == true
        }
        let original = try XCTUnwrap(measured.nativeViews["Button:One"])
        XCTAssertEqual(try XCTUnwrap(measured.frames["Button:One"]).width, 320, accuracy: 1)
        state.setState("$alignment", value: .string("center"))
        try await host.waitUntil("the committed center policy reaches the same native button probe") {
            measured.fillWidth["Button:One"] == false
        }
        let centered = try XCTUnwrap(measured.frames["Button:One"])
        XCTAssertLessThan(centered.width, 160)
        XCTAssertEqual(centered.midX, 160, accuracy: 1)
        XCTAssertTrue(measured.nativeViews["Button:One"] === original)
        XCTAssertEqual(measured.created["Button:One"], 1)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    }

    @MainActor func testOptionColumnsReflowTheSameNativeMedia() async throws {
        let library = try OpenUIComponents.library()
        let measured = IOSLayoutObservations()
        let registry = try observing(library.registry, names: ["Icon"], measured: measured)
        let state = OpenUIState(schema: library.library.toSchema())
        state.setSource(IOSNativeLayoutFixtures.options)
        let width = IOSValidationWidth(440)
        var presentation = OpenUIPresentation()
        presentation.minimumChoiceWidth = 200
        let host = try IOSNativeTestHost(IOSValidationWidthFixture(width: width) {
            OpenUIContentView(state: state, registry: registry)
                .openUIPresentation(presentation).dynamicTypeSize(.large)
        }, width: 900, height: 2200)
        defer { host.close() }
        try await host.waitUntil("all actual option media factories are mounted") {
            measured.frames.count == 3 && measured.nativeViews.count == 3
        }
        let original = measured.nativeViews.mapValues(ObjectIdentifier.init)
        for (value, columns) in [(CGFloat(440), 2), (800, 3), (280, 1), (600, 2)] {
            width.value = value
            try await host.waitUntil("the new viewport input reaches each existing native media probe") {
                measured.viewport.count == 3 && measured.viewport.values.allSatisfy { $0 == value }
            }
            XCTAssertEqual(Set(measured.frames.values.map { Int($0.minX.rounded()) }).count, columns)
            XCTAssertEqual(measured.nativeViews.mapValues(ObjectIdentifier.init), original)
        }
        XCTAssertEqual(measured.created.values.sorted(), [1, 1, 1])
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        try host.saveSnapshot(name: "options-reflow")
    }

    @MainActor func testImagesKeepTheirDeclaredRatioThroughRealLoadingAndPresentation() async throws {
        let source = "https://fixture.invalid/ios-card.png"
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let bytes = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 16, height: 9), format: format)
            .image { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 16, height: 9)) }.pngData())
        for (name, ratio) in [("wide", CGFloat(16) / 9), ("square", 1), ("portrait", 0.75)] {
            let library = try OpenUIComponents.library()
            let measured = IOSLayoutObservations()
            let registry = try observing(library.registry, names: ["Image"], measured: measured)
            let loader = IOSHeldImageLoader(source: source, bytes: bytes)
            let resources = OpenUIResourceContext(loader: loader)
            let state = OpenUIState(schema: library.library.toSchema())
            state.setSource("root=Image(\"Ratio artwork\",\"\(source)\")")
            let scoped = state.resourceStore.scoped(resources)
            let key = NativeResourceRequestID(request: try XCTUnwrap(scoped.request(for: source)),
                loader: ObjectIdentifier(scoped.loader), attempt: 0,
                authorizationScope: scoped.loader.authorizationScopeID)
            var presentation = OpenUIPresentation()
            presentation.coverAspectRatio = ratio
            presentation.motion.mediaRevealDuration = 0
            let host = try IOSNativeTestHost(OpenUIContentView(state: state, registry: registry)
                .openUIResourceContext(resources).openUIPresentation(presentation)
                .environment(\.colorScheme, .light)
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
                .frame(width: 320).fixedSize(horizontal: false, vertical: true), width: 320, height: 500)
            defer { loader.release(); host.close() }
            try await host.waitUntil("the real image transport is waiting and its placeholder is mounted") {
                loader.heldCount > 0 && measured.frames["Image:Ratio artwork"] != nil
            }
            let before = try XCTUnwrap(measured.frames["Image:Ratio artwork"])
            XCTAssertEqual(before.width, 320, accuracy: 1)
            XCTAssertEqual(before.height, 320 / ratio, accuracy: 1)
            XCTAssertNotEqual(state.mediaCache[key]?.wasPresented, true)
            try host.saveSnapshot(name: "image-\(name)-loading")
            loader.release()
            try await host.waitUntil("the decoded image is actually presented") { state.mediaCache[key]?.wasPresented == true }
            let after = try XCTUnwrap(measured.frames["Image:Ratio artwork"])
            XCTAssertEqual(after.width, before.width, accuracy: 1)
            XCTAssertEqual(after.height, before.height, accuracy: 1)
            let pixels = try redBounds(in: XCTUnwrap(host.snapshot().cgImage))
            XCTAssertEqual(pixels.width, 320, accuracy: 2, "The mounted image must contain decoded artwork, not only a cache entry")
            XCTAssertEqual(pixels.height, 320 / ratio, accuracy: 2)
            XCTAssertEqual(measured.created["Image:Ratio artwork"], 1)
            XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
            try host.saveSnapshot(name: "image-\(name)-loaded")
        }
    }

    @MainActor func testStreamingCardIDAndCompletionKeepTheMountedCardContent() async throws {
        let library = try OpenUIComponents.library()
        let measured = IOSLayoutObservations()
        let registry = try observing(library.registry, names: ["BoldText"], measured: measured)
        let state = OpenUIState(schema: library.library.toSchema())
        state.push(IOSNativeLayoutFixtures.streamingPrefix)
        let host = try IOSNativeTestHost(OpenUIContentView(state: state, registry: registry)
            .dynamicTypeSize(.large).frame(width: 320).fixedSize(horizontal: false, vertical: true), width: 320)
        defer { host.close() }
        try await host.waitUntil("the first referenced card is actually rendered") {
            measured.nativeViews["BoldText:First"] != nil && measured.frames["BoldText:First"] != nil
        }
        let first = try XCTUnwrap(measured.nativeViews["BoldText:First"])
        let revision = state.presentationRevision
        state.push(IOSNativeLayoutFixtures.streamingSuffix)
        state.complete()
        try await host.waitUntil("the second real card factory mounts its native content probe") {
            measured.nativeViews["BoldText:Second"] != nil && measured.frames["BoldText:Second"] != nil
        }
        XCTAssertTrue(state.isComplete)
        XCTAssertEqual(state.presentationRevision, revision)
        XCTAssertTrue(measured.nativeViews["BoldText:First"] === first)
        XCTAssertEqual(measured.created["BoldText:First"], 1)
        XCTAssertEqual(measured.removed["BoldText:First", default: 0], 0)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    }

    @MainActor private func observing(_ original: OpenUIComponentRegistry, names: [String],
        measured: IOSLayoutObservations) throws -> OpenUIComponentRegistry {
        var registry = original
        for name in names {
            let builder = try XCTUnwrap(original[name])
            registry[name] = { element, registry in
                let field = ["Image": "alt", "ImageTextLarge": "alt", "CompositeCardItem": "id",
                    "Button": "label", "BoldText": "value", "Icon": "name"][name] ?? "id"
                let key = name + ":" + (PropValue.string(element, field) ?? element.statementId ?? "")
                return AnyView(builder(element, registry).background(GeometryReader { geometry in
                    IOSLayoutIdentityMarker(key: key, measured: measured)
                        .onAppear { measured.frames[key] = geometry.frame(in: .global) }
                        .onChange(of: geometry.frame(in: .global)) { measured.frames[key] = $0 }
                }))
            }
            // Wrapping a factory must preserve all standard streaming, layout
            // and identity metadata. Tests observe the real renderer contract.
            registry.setPresentationPlaceholder(name, enabled: original.supportsPresentationPlaceholder(name))
            registry.setLayoutFields(name, fields: original.presentationLayoutFields(name))
            registry.setFormControlLabelOwner(name, enabled: original.ownsFormControlLabel(name))
            registry.setIdentityFields(name, fields: original.identityFields(for: name))
            registry.setPlaceholderFields(name, fields: original.presentationPlaceholderFields(name))
        }
        return registry
    }

    private func redBounds(in image: CGImage) throws -> CGRect {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var minX = image.width, minY = image.height, maxX = -1, maxY = -1
        for y in 0..<image.height { for x in 0..<image.width {
            let offset = y * context.bytesPerRow + x * 4
            if pixels[offset] > 204 && pixels[offset + 1] < 80 && pixels[offset + 2] < 80 && pixels[offset + 3] > 204 {
                minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
            }
        } }
        XCTAssertGreaterThanOrEqual(maxX, minX, "The actual UIKit capture must contain red image pixels")
        return maxX >= minX ? CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1) : .zero
    }
}

@MainActor private final class IOSLayoutObservations {
    var frames: [String: CGRect] = [:]
    var nativeViews: [String: UIView] = [:]
    var created: [String: Int] = [:]
    var removed: [String: Int] = [:]
    var fillWidth: [String: Bool] = [:]
    var viewport: [String: CGFloat] = [:]
}

private struct IOSLayoutIdentityMarker: UIViewRepresentable {
    let key: String
    let measured: IOSLayoutObservations
    @Environment(\.openUIFillControlWidth) private var fillWidth
    @Environment(\.iosValidationViewport) private var viewport
    func makeCoordinator() -> (String, IOSLayoutObservations) { (key, measured) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        measured.nativeViews[key] = view
        measured.created[key, default: 0] += 1
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        // These are the committed environment inputs reaching the mounted
        // native marker. They synchronize updates without waiting for the
        // dimensions asserted by the test or pretending to read SwiftUI AX.
        measured.fillWidth[key] = fillWidth
        measured.viewport[key] = viewport
    }
    static func dismantleUIView(_ view: UIView, coordinator: (String, IOSLayoutObservations)) {
        coordinator.1.removed[coordinator.0, default: 0] += 1
    }
}

private struct IOSValidationViewportKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
private extension EnvironmentValues {
    var iosValidationViewport: CGFloat {
        get { self[IOSValidationViewportKey.self] }
        set { self[IOSValidationViewportKey.self] = newValue }
    }
}

@MainActor private final class IOSValidationWidth: ObservableObject {
    @Published var value: CGFloat
    init(_ value: CGFloat) { self.value = value }
}

private struct IOSValidationWidthFixture<Content: View>: View {
    @ObservedObject var width: IOSValidationWidth
    @ViewBuilder let content: Content
    var body: some View {
        content.frame(width: width.value).fixedSize(horizontal: false, vertical: true)
            .environment(\.iosValidationViewport, width.value)
    }
}

/// The real resource transport is paused explicitly, not with a timing guess.
private final class IOSHeldImageLoader: OpenUIResourceLoading {
    private let source: String
    private let bytes: Data
    private let lock = NSLock()
    private var held: [CheckedContinuation<Data, Error>] = []
    private var released = false
    init(source: String, bytes: Data) { self.source = source; self.bytes = bytes }
    var heldCount: Int { lock.lock(); defer { lock.unlock() }; return held.count }
    func request(for source: String, relativeTo baseURL: URL?) -> URLRequest? {
        guard source == self.source, let url = URL(string: source, relativeTo: baseURL) else { return nil }
        return URLRequest(url: url)
    }
    func data(for request: URLRequest) async throws -> Data {
        guard request.url?.absoluteString == source else { throw URLError(.resourceUnavailable) }
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if released { lock.unlock(); continuation.resume(returning: bytes) }
            else { held.append(continuation); lock.unlock() }
        }
    }
    func release() {
        lock.lock(); released = true; let waiters = held; held.removeAll(); lock.unlock()
        waiters.forEach { $0.resume(returning: bytes) }
    }
}
#endif
