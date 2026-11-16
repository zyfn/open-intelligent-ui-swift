import SwiftLang
#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import SwiftOpenUI

final class ObjectCardCompositionTests: XCTestCase {
  @MainActor private func frames(_ source: String, width: CGFloat) throws -> [String: CGRect] {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let measured = ObjectCardFrames()
    var registry = library.registry
    for name in ["ImageTextLarge", "BoldText", "Button", "Image"] {
      let original = try XCTUnwrap(registry[name])
      registry[name] = { element, registry in
        AnyView(original(element, registry).background(GeometryReader { geometry in
          Color.clear.onAppear { measured.record(name, geometry.frame(in: .named("objects"))) }
            .onChange(of: geometry.frame(in: .named("objects"))) { measured.record(name, $0) }
        }))
      }
    }
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource(source)
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: registry)
      .frame(width: width).coordinateSpace(name: "objects"))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: width, height: 1800),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    window.setFrameOrigin(.init(x: -10000, y: -10000)); window.orderFront(nil)
    defer { window.close() }
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.12))
    host.layoutSubtreeIfNeeded()
    return measured.values
  }

  private var definitions: String {
    """
    heading=ImageTextLarge("", "Room", "A room by the lake", "One night", true)
    copy=Text("text", "A quiet room near the destination.")
    price=BoldText("number", "¥12,345", "Per night", "text", "lg")
    action=Button("Book room", @OpenUrl("https://example.invalid/room"), "primary", "normal", "small")
    """
  }
  private var single: String {
    """
    root=Stack([Card([Stack([heading]), Stack([copy]), footer], "card", "column", "m")])
    footer=Card([Stack([price]), Buttons([action], "row")], "clear", "row", "s", "center", "between", true)
    \(definitions)
    """
  }
  private var collection: String {
    """
    root=Stack([CompositeCardBlock([first, second], "grid", false)])
    first=CompositeCardItem("one", heading, [copy], {price:price, button:action})
    second=CompositeCardItem("two", heading, [copy], {price:price, button:action})
    \(definitions)
    """
  }

  @MainActor func testSingleAndCollectionUseTheSameHeaderInsetsAndFooterGeometry() throws {
    for width in [CGFloat(200), 344] {
      let one = try frames(single, width: width)
      let many = try frames(collection, width: width * 2 + 12)
      for name in ["ImageTextLarge", "BoldText", "Button"] {
        let a = try XCTUnwrap(one[name]), b = try XCTUnwrap(many[name])
        XCTAssertEqual(a.minX, b.minX, accuracy: 1, "\(name), card width \(width)")
        XCTAssertEqual(a.width, b.width, accuracy: 1, "\(name), card width \(width)")
        XCTAssertEqual(a.height, b.height, accuracy: 1, "\(name), card width \(width)")
        // Normalize to the header so a hosting window's vertical origin is irrelevant.
        XCTAssertEqual(a.minY - one["ImageTextLarge"]!.minY,
          b.minY - many["ImageTextLarge"]!.minY, accuracy: 1, name)
      }
      XCTAssertEqual(try XCTUnwrap(one["ImageTextLarge"]).minX, 16, accuracy: 1)
      XCTAssertEqual(try XCTUnwrap(one["ImageTextLarge"]).width, width - 32, accuracy: 1)
    }
  }

  @MainActor func testNarrowFootersWrapWithoutBreakingTheAmountOrLosingTheAction() throws {
    for source in [single, collection] {
      let narrow = try frames(source, width: source == single ? 200 : 412)
      let wide = try frames(source, width: source == single ? 344 : 700)
      let amount = try XCTUnwrap(narrow["BoldText"]), button = try XCTUnwrap(narrow["Button"])
      XCTAssertGreaterThanOrEqual(button.minY, amount.maxY + 7)
      XCTAssertEqual(amount.height, try XCTUnwrap(wide["BoldText"]).height, accuracy: 1)
      XCTAssertLessThanOrEqual(button.maxX, 184)
      XCTAssertGreaterThan(button.width, 40)
      XCTAssertLessThan(try XCTUnwrap(wide["Button"]).minY, try XCTUnwrap(wide["BoldText"]).maxY)
    }
  }

  @MainActor func testLeadingImagesFillCardEdgesWhileBodyImagesRetainTheirInset() throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    var theme = OpenUIThemeValues()
    // Geometry must be measured with loaded artwork. A compact placeholder
    // glyph cannot establish the image's full bounds.
    theme.sunk = .blue; theme.foreground = .white
    let imageSource = "https://fixture.invalid/card.png"
    let pixels = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
      pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 4, bitsPerPixel: 32))
    pixels.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: 0, y: 0)
    let loader = ObjectCardImageLoader(source: imageSource,
      bytes: try XCTUnwrap(pixels.representation(using: .png, properties: [:])))
    let resources = OpenUIResourceContext(loader: loader)
    var presentation = OpenUIPresentation()
    presentation.motion.mediaRevealDuration = 0
    func bitmap(_ source: String, name: String, width: CGFloat = 320) throws -> NSBitmapImageRep {
      let state = OpenUIState(schema: library.library.toSchema()); state.setSource(source)
      XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
      let scoped = state.resourceStore.scoped(resources)
      let key = NativeResourceRequestID(request: try XCTUnwrap(scoped.request(for: imageSource)),
        loader: ObjectIdentifier(scoped.loader), attempt: 0,
        authorizationScope: scoped.loader.authorizationScopeID)
      let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
        .openUIResourceContext(resources).openUITheme(theme).openUIPresentation(presentation)
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
        .frame(width: width).background(.white).environment(\.colorScheme, .light))
      let window = NSWindow(contentRect: .init(origin: .zero, size: host.fittingSize),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
      window.contentView = host
      window.setFrameOrigin(.init(x: -10000, y: -10000)); window.orderFront(nil)
      defer { window.close() }
      // Exercise the real loader, decode, environment scope and reveal lifecycle.
      // A synchronous ImageRenderer cannot establish that the native media view
      // actually presented the entry merely by seeding wasPresented in its cache.
      let expectsArtwork = source.contains(imageSource)
      let deadline = Date().addingTimeInterval(3)
      repeat {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
      } while expectsArtwork && state.mediaCache[key]?.wasPresented != true && Date() < deadline
      if expectsArtwork {
        XCTAssertTrue(state.mediaCache[key]?.wasPresented == true,
          "\(name): artwork must be decoded and presented before testing geometry; cache entry=\(state.mediaCache[key] != nil)")
      }
      window.setContentSize(host.fittingSize)
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
      let captured = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: captured)
      // Normalize backing scale so the original samples remain point-for-pixel
      // comparisons on Retina and non-Retina runners alike.
      let canvas = try XCTUnwrap(CGContext(data: nil, width: Int(ceil(host.bounds.width)),
        height: Int(ceil(host.bounds.height)), bitsPerComponent: 8,
        bytesPerRow: Int(ceil(host.bounds.width)) * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      canvas.setFillColor(CGColor(gray: 1, alpha: 1))
      canvas.fill(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
      canvas.draw(try XCTUnwrap(captured.cgImage),
        in: CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
      let image = NSBitmapImageRep(cgImage: try XCTUnwrap(canvas.makeImage()))
      if let directory = ProcessInfo.processInfo.environment["OPENUI_SNAPSHOT_DIR"] {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try XCTUnwrap(image.representation(using: .png, properties: [:]))
          .write(to: URL(fileURLWithPath: directory).appendingPathComponent("object-card-" + name + ".png"))
      }
      return image
    }
    func sample(_ image: NSBitmapImageRep, x: Int, y: Int) throws -> (isRed: Bool, detail: String) {
      let color = try XCTUnwrap(image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
        "Sample (\(x),\(y)) must be inside bitmap \(image.pixelsWide)x\(image.pixelsHigh)")
      return (color.redComponent > 0.8 && color.greenComponent < 0.5 && color.blueComponent < 0.5,
        "sample (\(x),\(y)) RGBA=(\(color.redComponent),\(color.greenComponent),\(color.blueComponent),\(color.alphaComponent)), bitmap=\(image.pixelsWide)x\(image.pixelsHigh)")
    }
    for (name, source) in [
      ("leading-image", "root=Card([Image(\"photo\",\"\(imageSource)\"),CardHeader(\"Title\")],\"card\")"),
      ("leading-banner", "root=Card([Stack([ImageTextLarge(\"\(imageSource)\",\"photo\",\"Title\")])],\"card\")"),
      ("leading-grid", "root=CompositeCardBlock([CompositeCardItem(\"a\",ImageTextLarge(\"\(imageSource)\",\"photo\",\"Title\"),[]),CompositeCardItem(\"b\",ImageTextLarge(\"\(imageSource)\",\"photo\",\"Title\"),[])],\"grid\",false)")
    ] {
      let image = try bitmap(source, name: name, width: source.contains("CompositeCardBlock") ? 652 : 320)
      let left = try sample(image, x: 5, y: 60), top = try sample(image, x: 60, y: 5)
      XCTAssertTrue(left.isRed, "Leading image must reach the card's left edge; \(name): \(left.detail)")
      XCTAssertTrue(top.isRed, "Leading image must reach the card's top edge; \(name): \(top.detail)")
    }
    let body = try bitmap("root=Card([CardHeader(\"Title\"),Image(\"body\",\"\(imageSource)\")],\"card\")", name: "body-image")
    let outside = try sample(body, x: 5, y: 100), inside = try sample(body, x: 40, y: 100)
    XCTAssertFalse(outside.isRed, "Body image must not extend through its surrounding content inset; \(outside.detail)")
    XCTAssertTrue(inside.isRed, "Body image must render within its content inset; \(inside.detail)")

    let missing = try bitmap("root=Card([Image(\"No source\"),CardHeader(\"Title\")],\"card\")", name: "missing-image")
    for (x, y) in [(5, 60), (60, 5), (160, 60)] {
      let color = try XCTUnwrap(missing.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
      let detail = try sample(missing, x: x, y: y).detail
      XCTAssertGreaterThan(color.redComponent, 0.9, "Missing artwork must leave the white card surface visible; \(detail)")
      XCTAssertGreaterThan(color.greenComponent, 0.9, detail)
      XCTAssertGreaterThan(color.blueComponent, 0.9, detail)
    }
  }

  @MainActor func testWrappingCardsKeepReadingSpaceAndFillAnIncompleteRow() throws {
    let cases: [(CGFloat, [CGFloat])] = [(320, [320, 320, 320]),
      (350, [169, 169, 350]), (530, [506 / 3, 506 / 3, 506 / 3])]
    for (width, expected) in cases {
      let source = "root=Stack([Card([Image(\"a\")],\"clear\"),Card([Image(\"b\")],\"clear\"),Card([Image(\"c\")],\"clear\")],\"row\",\"m\",\"start\",\"start\",true)"
      // Individual Image names are recorded separately by their alt in a dedicated probe below.
      let measured = try imageFrames(source, width: width)
      for (index, key) in ["a", "b", "c"].enumerated() {
        XCTAssertEqual(try XCTUnwrap(measured[key]).width, expected[index], accuracy: 1)
      }
      if width == 350 {
        XCTAssertEqual(try XCTUnwrap(measured["a"]).minY, try XCTUnwrap(measured["b"]).minY, accuracy: 1)
        XCTAssertGreaterThan(try XCTUnwrap(measured["c"]).minY, try XCTUnwrap(measured["a"]).maxY)
      }
    }
  }

  @MainActor private func imageFrames(_ source: String, width: CGFloat) throws -> [String: CGRect] {
    let library = try OpenUIComponents.library()
    let measured = ObjectCardFrames()
    var registry = library.registry
    let original = try XCTUnwrap(registry["Image"])
    registry["Image"] = { element, registry in
      AnyView(original(element, registry).background(GeometryReader { geometry in
        Color.clear.onAppear { measured.values[PropValue.string(element, "alt") ?? ""] = geometry.frame(in: .global) }
          .onChange(of: geometry.frame(in: .global)) { measured.values[PropValue.string(element, "alt") ?? ""] = $0 }
      }))
    }
    let state = OpenUIState(schema: library.library.toSchema()); state.setSource(source)
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: registry).frame(width: width))
    let window = NSWindow(contentRect: .init(x: -10000, y: -10000, width: width, height: 1600),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
    defer { window.close() }
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.12))
    return measured.values
  }

  @MainActor func testImagesWaitForUnknownRowContributorsThenStayFixedWhileCopyGrows() throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    var registry = library.registry
    let original = try XCTUnwrap(registry["Image"])
    let measured = ObjectCardFrames()
    registry["Image"] = { element, registry in
      AnyView(original(element, registry).background(GeometryReader { geometry in
        Color.clear.onAppear { measured.values[PropValue.string(element, "alt") ?? ""] = geometry.frame(in: .global) }
          .onChange(of: geometry.frame(in: .global)) { measured.values[PropValue.string(element, "alt") ?? ""] = $0 }
      }))
    }
    let state = OpenUIState(schema: library.library.toSchema())
    state.push("root=Stack([a,b],\"row\",\"m\",\"start\",\"start\",true)\na=Card([Image(\"a\")],\"clear\")\n")
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: registry).frame(width: 350))
    let window = NSWindow(contentRect: .init(x: -10000, y: -10000, width: 350, height: 1400),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
    defer { window.close() }
    func settle() { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.12)) }
    settle()
    XCTAssertLessThan(try XCTUnwrap(measured.values["a"]).height, 40,
      "Only compact pending feedback, not a full-width picture, may appear while a sibling's role is unknown")
    state.push("b=Card([Image(\"b\"),copy],\"clear\")\ncopy=TextContent(\"Short")
    settle()
    let before = try XCTUnwrap(measured.values["a"])
    XCTAssertEqual(before.width, 169, accuracy: 1)
    XCTAssertEqual(before.height, 169 * 9 / 16, accuracy: 1)
    state.push(" copy that grows across many lines inside the same reading column.")
    settle()
    XCTAssertEqual(try XCTUnwrap(measured.values["a"]).width, before.width, accuracy: 1)
    XCTAssertEqual(try XCTUnwrap(measured.values["a"]).height, before.height, accuracy: 1)
    state.push("\")"); state.complete(); settle()
    XCTAssertEqual(try XCTUnwrap(measured.values["a"]).width, before.width, accuracy: 1)
  }
}

@MainActor private final class ObjectCardFrames {
  var values: [String: CGRect] = [:]
  func record(_ name: String, _ frame: CGRect) {
    if values[name] == nil || frame.minX <= values[name]!.minX { values[name] = frame }
  }
}

/// Real resource loading and decoding, with deterministic bytes and no network.
private final class ObjectCardImageLoader: OpenUIResourceLoading {
  private let source: String
  private let bytes: Data
  init(source: String, bytes: Data) { self.source = source; self.bytes = bytes }
  func request(for source: String, relativeTo baseURL: URL?) -> URLRequest? {
    guard source == self.source, let url = URL(string: source, relativeTo: baseURL) else { return nil }
    return URLRequest(url: url)
  }
  func data(for request: URLRequest) async throws -> Data {
    guard request.url?.absoluteString == source else { throw URLError(.resourceUnavailable) }
    return bytes
  }
}
#endif
