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

  @MainActor func testContentImagesPreserveTheirPixelsAndCardInsets() throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    var theme = OpenUIThemeValues()
    // Geometry must be measured with loaded artwork. A compact placeholder
    // glyph cannot establish the image's full bounds.
    theme.sunk = .green
    theme.foreground = .white
    theme.imagePlaceholderBackground = Color(red: 0, green: 0, blue: 1)
    let imageSource = "https://fixture.invalid/card.png"
    let pixels = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
      pixelsWide: 16, pixelsHigh: 9, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 16 * 4, bitsPerPixel: 32))
    // Match the declared slot to isolate container insets from image fitting.
    for y in 0..<9 { for x in 0..<16 {
      pixels.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y)
    } }
    var imageBytes = try XCTUnwrap(pixels.representation(using: .png, properties: [:]))
    var presentation = OpenUIPresentation()
    presentation.motion.mediaRevealDuration = 0
    func bitmap(_ source: String, name: String, width: CGFloat = 320) throws -> NSBitmapImageRep {
      let loader = ObjectCardImageLoader(source: imageSource, bytes: imageBytes)
      let resources = OpenUIResourceContext(loader: loader)
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
      XCTAssertLessThan(color.redComponent, 0.1, "Missing content images retain their declared media surface; \(detail)")
      XCTAssertLessThan(color.greenComponent, 0.1, detail)
      XCTAssertGreaterThan(color.blueComponent, 0.9, detail)
    }

    // Standard images fill their declared cover slot. Matching proportions
    // preserve the corner markers; square and portrait images crop them.
    func cornerImage(width: Int, height: Int) throws -> Data {
      let pixels = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: width * 4, bitsPerPixel: 32))
      let marker = min(width, height) * 15 / 100
      for y in 0..<height { for x in 0..<width {
        let color: NSColor
        if x < marker && y < marker { color = NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1) }
        else if x >= width - marker && y < marker { color = NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1) }
        else if x < marker && y >= height - marker { color = NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1) }
        else if x >= width - marker && y >= height - marker { color = NSColor(deviceRed: 1, green: 1, blue: 0, alpha: 1) }
        else { color = .white }
        pixels.setColor(color, atX: x, y: y)
      } }
      return try XCTUnwrap(pixels.representation(using: .png, properties: [:]))
    }
    func markerColors(_ image: NSBitmapImageRep) throws -> Set<String> {
      var colors: Set<String> = []
      for y in stride(from: 4, to: image.pixelsHigh, by: 8) {
        for x in stride(from: 4, to: image.pixelsWide, by: 8) {
          let c = try XCTUnwrap(image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
          if c.redComponent > 0.9 && c.greenComponent < 0.1 && c.blueComponent < 0.1 { colors.insert("red") }
          if c.redComponent < 0.1 && c.greenComponent > 0.9 && c.blueComponent < 0.1 { colors.insert("green") }
          if c.redComponent < 0.1 && c.greenComponent < 0.1 && c.blueComponent > 0.9 { colors.insert("blue") }
          if c.redComponent > 0.9 && c.greenComponent > 0.9 && c.blueComponent < 0.1 { colors.insert("yellow") }
        }
      }
      return colors
    }
    for (name, source, empty) in [
      ("complete-image", "root=Image(\"Corners\",\"\(imageSource)\")", "root=Image(\"Corners\")"),
      ("complete-block", "root=ImageBlock(\"\(imageSource)\",\"Corners\")", "root=ImageBlock(\"\",\"Corners\")")
    ] {
      let placeholder = try bitmap(empty, name: name + "-placeholder")
      XCTAssertEqual(placeholder.pixelsWide, 320)
      XCTAssertEqual(placeholder.pixelsHigh, 180)
      for (width, height, keepsCorners) in [(100, 100, false), (160, 90, true), (80, 120, false)] {
        imageBytes = try cornerImage(width: width, height: height)
        let loaded = try bitmap(source, name: name + "-\(width)x\(height)")
        XCTAssertEqual(try markerColors(loaded), keepsCorners ? Set(["red", "green", "blue", "yellow"]) : [],
          "\(name) must fill its cover slot, cropping only the source area outside it")
        XCTAssertEqual(loaded.pixelsWide, 320, "Content images use the full available width")
        XCTAssertEqual(loaded.pixelsHigh, 180,
          "Loading and loaded images keep the same declared cover height")
      }
    }
    let banner = try bitmap("root=ImageTextLarge(\"\(imageSource)\",\"Corners\",\"Banner\")", name: "cropped-banner")
    XCTAssertTrue(try markerColors(banner).isEmpty,
      "A banner still fills its declared photo slot rather than acquiring content-image margins")
  }

  @MainActor func testWrappingCardsKeepReadingSpaceAndFillAnIncompleteRow() throws {
    func source(count: Int, detail: String) -> String {
      let cards = ["a", "b", "c"].prefix(count).map { key in
        #"Card([Image("\#(key)"),CardHeader("完整的图文对象标题 \#(key)","独立的辅助说明"),TextContent("\#(detail)")],"clear","column","xs")"#
      }
      return #"root=Stack([\#(cards.joined(separator: ","))],"row","m","start","start",true)"#
    }
    let detail = "说明保持完整换行，标题与图片一起参与同一张卡片的实际布局。"
    let cases: [(CGFloat, [CGFloat])] = [(320, [320, 320, 320]),
      (350, [169, 169, 350]), (530, [506 / 3, 506 / 3, 506 / 3])]
    for (width, expected) in cases {
      let measured = try imageFrames(source(count: 3, detail: detail), width: width)
      for (index, key) in ["a", "b", "c"].enumerated() {
        XCTAssertEqual(try XCTUnwrap(measured[key]).width, expected[index], accuracy: 1)
      }
      if width == 350 {
        XCTAssertEqual(try XCTUnwrap(measured["a"]).minY, try XCTUnwrap(measured["b"]).minY, accuracy: 1)
        XCTAssertGreaterThan(try XCTUnwrap(measured["c"]).minY, try XCTUnwrap(measured["a"]).maxY)
      }
    }
    // A 390 pt preview with 20 pt side insets has 350 pt available. Two
    // complete image/title/body cards must share it even as their copy grows.
    for text in [detail, String(repeating: detail, count: 5)] {
      let measured = try imageFrames(source(count: 2, detail: text), width: 350)
      let first = try XCTUnwrap(measured["a"]), second = try XCTUnwrap(measured["b"])
      XCTAssertEqual(first.width, 169, accuracy: 1)
      XCTAssertEqual(second.width, 169, accuracy: 1)
      XCTAssertEqual(first.minY, second.minY, accuracy: 1,
        "Long titles and body copy must wrap inside the two allocated columns")
      XCTAssertEqual(second.minX - first.maxX, 12, accuracy: 1)
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
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: registry)
      .dynamicTypeSize(.large).frame(width: width))
    let window = NSWindow(contentRect: .init(x: -10000, y: -10000, width: width, height: 1600),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
    defer { window.close() }
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.12))
    return measured.values
  }

  @MainActor func testStreamingCardCopyKeepsMixedRowWidthsStable() async throws {
    _ = NativeAccessibilityTestSupport.application
    for (variant, alignment) in [("clear", "start"), ("card", "stretch")] {
      let library = try OpenUIComponents.library()
      var registry = library.registry
      let registrations = ["Image", "TextContent"].map { name in
        (name: name, placeholder: registry.supportsPresentationPlaceholder(name),
         layout: registry.presentationLayoutFields(name), labels: registry.ownsFormControlLabel(name),
         identity: registry.identityFields(for: name), placeholderFields: registry.presentationPlaceholderFields(name))
      }
      let image = try XCTUnwrap(registry["Image"])
      let text = try XCTUnwrap(registry["TextContent"])
      let frames = ObjectCardFrames()
      let directions = "出站后沿湖边步道一直走到公交站"
      registry["Image"] = { element, registry in
        AnyView(image(element, registry).background(GeometryReader { geometry in
          Color.clear.onAppear { frames.values["cover"] = geometry.frame(in: .global) }
            .onChange(of: geometry.frame(in: .global)) { frames.values["cover"] = $0 }
        }))
      }
      registry["TextContent"] = { element, registry in
        let content = text(element, registry)
        guard PropValue.string(element, "text") == directions else { return content }
        return AnyView(content.background(GeometryReader { geometry in
          Color.clear.onAppear { frames.values["directions"] = geometry.frame(in: .global) }
            .onChange(of: geometry.frame(in: .global)) { frames.values["directions"] = $0 }
        }))
      }
      // Geometry observers must retain the standard renderers' streaming and
      // identity contracts; assigning a builder clears their registration metadata.
      for registration in registrations {
        registry.setPresentationPlaceholder(registration.name, enabled: registration.placeholder)
        registry.setLayoutFields(registration.name, fields: registration.layout)
        registry.setFormControlLabelOwner(registration.name, enabled: registration.labels)
        registry.setIdentityFields(registration.name, fields: registration.identity)
        registry.setPlaceholderFields(registration.name, fields: registration.placeholderFields)
      }

      let state = OpenUIState(schema: library.library.toSchema())
      state.push("""
        root=Stack([card,directions],"row","m","\(alignment)","start",false)
        directions=TextContent("\(directions)")
        card=Card([Image("湖边"),copy],"\(variant)")
        copy=TextContent("先到西湖
        """)
      let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: registry)
        .dynamicTypeSize(.large).frame(width: 350))
      let window = NSWindow(contentRect: .init(x: -10000, y: -10000, width: 350, height: 900),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
      defer { window.close() }
      try await NativeAccessibilityTestSupport.activate(in: host)
      let initialCopy = "先到西湖"
      let appendedCopy = "先到西湖，再沿着湖边步道散步，看完夕阳之后可以到附近的小店休息。"
      var initialGeometry = "not yet measured"
      func parsedCopy() -> String? {
        guard let root = state.root,
          let card = PropValue.children(root).first(where: { $0.statementId == "card" }),
          let copy = PropValue.children(card).first(where: { $0.statementId == "copy" }) else { return nil }
        return PropValue.string(copy, "text")
      }
      func failureContext(_ stage: String) -> String {
        let rendered = NativeAccessibilityTestSupport.renderedText(in: host)
        let geometry = "fitting=\(host.fittingSize), cover=\(String(describing: frames.values["cover"])), directions=\(String(describing: frames.values["directions"]))"
        var snapshot = "unavailable"
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
          host.cacheDisplay(in: host.bounds, to: bitmap)
          if let data = bitmap.representation(using: .png, properties: [:]) {
            let output = ProcessInfo.processInfo.environment["OPENUI_SNAPSHOT_DIR"]
            let directory = output.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
              .map { $0.appendingPathComponent("observation-diagnostics", isDirectory: true) }
              ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("outputs/verification/observation-diagnostics", isDirectory: true)
            let destination = directory.appendingPathComponent("object-card-streaming-\(variant)-\(alignment)-\(stage).png")
            do {
              try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
              try data.write(to: destination)
              snapshot = destination.path
            } catch { snapshot = "could not save: \(error)" }
          }
        }
        return "variant=\(variant), alignment=\(alignment), stage=\(stage), source=\(String(describing: parsedCopy())), complete=\(state.isComplete), initial=\(initialGeometry), current=\(geometry), rendered=\(rendered), snapshot=\(snapshot)"
      }
      enum ObservationFailure: Error { case timeout }
      func waitForCopy(_ expected: String, stage: String) async throws {
        let deadline = Date().addingTimeInterval(5)
        repeat {
          host.layoutSubtreeIfNeeded()
          let rendered = NativeAccessibilityTestSupport.renderedText(in: host)
          if rendered.contains(expected), rendered.contains(directions),
            frames.values["cover"] != nil, frames.values["directions"] != nil {
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            return
          }
          // A run-loop delay alone does not complete the coalescing Task and
          // Markdown worker. Yield until the actual native text is visible;
          // the height being asserted is never part of this readiness condition.
          try await Task.sleep(nanoseconds: 10_000_000)
        } while Date() < deadline
        XCTFail("Timed out waiting for rendered copy \(expected); \(failureContext(stage))")
        throw ObservationFailure.timeout
      }

      XCTAssertEqual(parsedCopy(), initialCopy, failureContext("initial-source"))
      try await waitForCopy(initialCopy, stage: "initial")
      let initialCover = try XCTUnwrap(frames.values["cover"])
      let initialDirections = try XCTUnwrap(frames.values["directions"])
      let initialHeight = host.fittingSize.height
      let revision = state.presentationRevision
      initialGeometry = "height=\(initialHeight), cover=\(initialCover), directions=\(initialDirections)"
      XCTAssertGreaterThan(initialCover.width, 0, failureContext("initial"))
      XCTAssertGreaterThan(initialDirections.width, 0, failureContext("initial"))
      state.push("，再沿着湖边步道散步，看完夕阳之后可以到附近的小店休息。")
      XCTAssertEqual(parsedCopy(), appendedCopy, failureContext("append-source"))
      XCTAssertFalse(state.isComplete, failureContext("append-source"))
      try await waitForCopy(appendedCopy, stage: "append")

      let finalCover = try XCTUnwrap(frames.values["cover"])
      let finalDirections = try XCTUnwrap(frames.values["directions"])
      XCTAssertEqual(finalCover.width, initialCover.width, accuracy: 1,
        "Streaming Card copy must stay within its allocated column; \(failureContext("append"))")
      XCTAssertEqual(finalDirections.width, initialDirections.width, accuracy: 1, failureContext("append"))
      XCTAssertEqual(finalDirections.minX, initialDirections.minX, accuracy: 1, failureContext("append"))
      XCTAssertGreaterThan(host.fittingSize.height, initialHeight, failureContext("append"))

      state.push("\")")
      state.complete()
      try await waitForCopy(appendedCopy, stage: "complete")
      XCTAssertEqual(parsedCopy(), appendedCopy, failureContext("complete"))
      XCTAssertTrue(state.isComplete, failureContext("complete"))
      XCTAssertEqual(state.presentationRevision, revision, failureContext("complete"))
      XCTAssertEqual(try XCTUnwrap(frames.values["cover"]).width, initialCover.width, accuracy: 1, failureContext("complete"))
      XCTAssertEqual(try XCTUnwrap(frames.values["directions"]).width, initialDirections.width, accuracy: 1, failureContext("complete"))
      XCTAssertTrue(state.errors.isEmpty, "\(state.errors); \(failureContext("complete"))")
    }
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
    state.push("$surface=\"clear\"\nroot=Stack([a,b],\"row\",\"m\",\"start\",\"start\",true)\na=Card([Image(\"a\"),Form(\"draft\",Buttons([]),[FormControl(\"Note\",Input(\"note\"))])],$surface)\n")
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: registry)
      .dynamicTypeSize(.large).frame(width: 350))
    let window = NSWindow(contentRect: .init(x: -10000, y: -10000, width: 350, height: 1400),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
    defer { window.close() }
    func settle() { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.12)) }
    settle()
    XCTAssertLessThan(try XCTUnwrap(measured.values["a"]).height, 40,
      "Only compact pending feedback, not a full-width picture, may appear while a sibling's role is unknown")
    state.push("b=Card([Image(\"b\"),copy],$surface)\ncopy=TextContent(\"Short")
    settle()
    let before = try XCTUnwrap(measured.values["a"])
    XCTAssertEqual(before.width, 169, accuracy: 1)
    XCTAssertEqual(before.height, 169 * 9 / 16, accuracy: 1,
      "An unknown source reserves the cover slot inside its allocated column")
    state.push(" copy that grows across many lines inside the same reading column.")
    settle()
    XCTAssertEqual(try XCTUnwrap(measured.values["a"]).width, before.width, accuracy: 1)
    XCTAssertEqual(try XCTUnwrap(measured.values["a"]).height, before.height, accuracy: 1)
    state.push("\")"); state.complete(); settle()
    XCTAssertEqual(try XCTUnwrap(measured.values["a"]).width, before.width, accuracy: 1)

    // Layout fields can change through a component-local update after the
    // document completes. The parent must reallocate its existing children.
    let sourceRevision = state.sourceRevision, presentationRevision = state.presentationRevision
    state.setFieldValue(form: "draft", name: "note", value: .string("Keep this edit"))
    settle()
    let inset = OpenUIThemeValues.defaults.componentStyle.panelInset
    for (surface, expectedWidth) in [("card", 350 - 2 * inset), ("clear", CGFloat(169))] {
      state.setState("$surface", value: .string(OpenUIString(surface))); settle()
      XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
      let first = try XCTUnwrap(measured.values["a"]), second = try XCTUnwrap(measured.values["b"])
      XCTAssertEqual(first.width, expectedWidth, accuracy: 1)
      XCTAssertEqual(second.width, expectedWidth, accuracy: 1)
      if surface == "card" {
        XCTAssertEqual(first.minX, second.minX, accuracy: 1)
        XCTAssertGreaterThan(second.minY, first.maxY, "The larger card basis must wrap the existing row")
      } else {
        XCTAssertEqual(first.minY, second.minY, accuracy: 1)
        XCTAssertEqual(second.minX - first.maxX, 12, accuracy: 1)
      }
      XCTAssertEqual(state.sourceRevision, sourceRevision)
      XCTAssertEqual(state.presentationRevision, presentationRevision, "Reflow must not replace the document")
      XCTAssertEqual(state.fieldValue(form: "draft", name: "note"), .string("Keep this edit"))
    }
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
