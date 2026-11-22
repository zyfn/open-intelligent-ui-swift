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
    for name in ["ImageTextLarge", "Text", "BoldText", "Button", "Image"] {
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

  @MainActor func testSingleAndCollectionRespectTheirHeaderAndExplicitFooterInsets() throws {
    let theme = OpenUIThemeValues.defaults
    let border = OpenUIPresentation.defaults.borderWidth
    let collectionInset = theme.componentStyle.panelInset
    let singleFooterInset = 2 * border + theme.spaceL
    for width in [CGFloat(200), 344] {
      let one = try frames(single, width: width)
      let many = try frames(collection, width: width * 2 + 12)
      let header = try XCTUnwrap(one["ImageTextLarge"])
      let collectionHeader = try XCTUnwrap(many["ImageTextLarge"])
      // Keep the original Lang. Upstream card.scss (7b7a519) gives standard
      // card no padding and a real border; its explicit clear footer adds
      // horizontal space-l and its own border. CompositeCardItem retains its
      // dedicated panel inset and leading-artwork presentation.
      XCTAssertEqual(header.minX, border, accuracy: 1)
      XCTAssertEqual(header.width, width - 2 * border, accuracy: 1)
      XCTAssertEqual(collectionHeader.minX, collectionInset, accuracy: 1)
      XCTAssertEqual(collectionHeader.width, width - 2 * collectionInset, accuracy: 1)
      let naturalHeader = try XCTUnwrap(try frames("root=heading\n\(definitions)",
        width: width - 2 * border)["ImageTextLarge"])
      XCTAssertEqual(header.height, naturalHeader.height, accuracy: 1,
        "Standard Card must not apply a hidden negative media inset to its header")

      for name in ["BoldText", "Button"] {
        let a = try XCTUnwrap(one[name]), b = try XCTUnwrap(many[name])
        let inward = singleFooterInset - collectionInset
        let shift = name == "Button" && width == 344 ? -inward : inward
        XCTAssertEqual(a.minX, b.minX + shift, accuracy: 1, "\(name), card width \(width)")
        XCTAssertEqual(a.width, b.width, accuracy: 1, "\(name), card width \(width)")
        XCTAssertEqual(a.height, b.height, accuracy: 1, "\(name), card width \(width)")
      }
      for (measured, footerBorder) in [(one, border), (many, CGFloat.zero)] {
        let heading = try XCTUnwrap(measured["ImageTextLarge"])
        let copy = try XCTUnwrap(measured["Text"])
        let amount = try XCTUnwrap(measured["BoldText"])
        let button = try XCTUnwrap(measured["Button"])
        // The wider standard header/body can wrap differently. Assert their
        // actual content relationships instead of equating two different boxes.
        XCTAssertEqual(copy.minY - heading.maxY, theme.spaceM, accuracy: 1)
        XCTAssertEqual(min(amount.minY, button.minY) - copy.maxY,
          theme.spaceM + footerBorder, accuracy: 1)
      }
      XCTAssertEqual(try XCTUnwrap(one["BoldText"]).minX, singleFooterInset, accuracy: 1)
      XCTAssertEqual(try XCTUnwrap(many["BoldText"]).minX, collectionInset, accuracy: 1)
    }
  }

  @MainActor func testNarrowFootersWrapWithoutBreakingTheAmountOrLosingTheAction() throws {
    for source in [single, collection] {
      let narrow = try frames(source, width: source == single ? 200 : 412)
      let wide = try frames(source, width: source == single ? 344 : 700)
      let amount = try XCTUnwrap(narrow["BoldText"]), button = try XCTUnwrap(narrow["Button"])
      XCTAssertGreaterThanOrEqual(button.minY, amount.maxY + 7)
      XCTAssertEqual(amount.height, try XCTUnwrap(wide["BoldText"]).height, accuracy: 1)
      let theme = OpenUIThemeValues.defaults
      let inset = source == single ? 2 * OpenUIPresentation.defaults.borderWidth + theme.spaceL
        : theme.componentStyle.panelInset
      XCTAssertLessThanOrEqual(button.maxX, 200 - inset)
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
      let dedicated = source.contains("CompositeCardBlock")
      let image = try bitmap(source, name: name, width: dedicated ? 652 : 320)
      let left = try sample(image, x: 5, y: 60), top = try sample(image, x: 60, y: 5)
      XCTAssertTrue(left.isRed, "Leading artwork keeps its declared content width; \(name): \(left.detail)")
      XCTAssertTrue(top.isRed, "Leading artwork keeps its declared content origin; \(name): \(top.detail)")
      if !dedicated {
        // Upstream card.scss (7b7a519) has zero card padding plus a real border.
        // Standard Card adds no media bleed or top-only image corner treatment.
        let borderLeft = try sample(image, x: 0, y: 60), borderTop = try sample(image, x: 60, y: 0)
        XCTAssertFalse(borderLeft.isRed, "The transparent border still reserves horizontal space; \(borderLeft.detail)")
        XCTAssertFalse(borderTop.isRed, "The transparent border still reserves vertical space; \(borderTop.detail)")
        let imageHeight = (320 - 2 * presentation.borderWidth) / presentation.coverAspectRatio
        let topCorner = try sample(image, x: 1, y: 1)
        let bottomCorner = try sample(image, x: 1, y: Int(presentation.borderWidth + imageHeight) - 1)
        XCTAssertFalse(topCorner.isRed, "The image retains its own top corner; \(name): \(topCorner.detail)")
        XCTAssertFalse(bottomCorner.isRed, "The image retains its own bottom corner; \(name): \(bottomCorner.detail)")
      }
    }
    let body = try bitmap("root=Card([CardHeader(\"Title\"),Image(\"body\",\"\(imageSource)\")],\"card\")", name: "body-image")
    let border = try sample(body, x: 0, y: 100)
    let nearEdge = try sample(body, x: 5, y: 100), inside = try sample(body, x: 40, y: 100)
    XCTAssertFalse(border.isRed, "Body media cannot paint over the standard Card's border box; \(border.detail)")
    XCTAssertTrue(nearEdge.isRed, "Zero card padding applies to body media as well as leading media; \(nearEdge.detail)")
    XCTAssertTrue(inside.isRed, "Body image must render within its declared content box; \(inside.detail)")

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

  @MainActor func testWrappingCardsShareTheRowWithoutNativeReadingWidthBreakpoints() throws {
    func source(count: Int, detail: String) -> String {
      let cards = ["a", "b", "c"].prefix(count).map { key in
        #"Card([Image("\#(key)"),CardHeader("完整的图文对象标题 \#(key)","独立的辅助说明"),TextContent("\#(detail)")],"clear","column","xs")"#
      }
      return #"root=Stack([\#(cards.joined(separator: ","))],"row","m","start","start",true)"#
    }
    let detail = "说明保持完整换行，标题与图片一起参与同一张卡片的实际布局。"
    let clearInset = OpenUIThemeValues.defaults.spaceL + OpenUIPresentation.defaults.borderWidth
    // Upstream flex:1/min-width:0 replaces the native 160 pt reading basis.
    // Retain the historical Lang and test it at all of its original widths.
    for width in [CGFloat(320), 350, 530] {
      let measured = try imageFrames(source(count: 3, detail: detail), width: width)
      let first = try XCTUnwrap(measured["a"])
      let cell = (width - 24) / 3
      for (index, key) in ["a", "b", "c"].enumerated() {
        let frame = try XCTUnwrap(measured[key])
        XCTAssertEqual(frame.width, cell - 2 * clearInset, accuracy: 1)
        XCTAssertEqual(frame.minX, CGFloat(index) * (cell + 12) + clearInset, accuracy: 1)
        XCTAssertEqual(frame.minY, first.minY, accuracy: 1,
          "All three flexible cards fit; text wraps within each allocated content column")
      }
    }
    // A 390 pt preview with 20 pt side insets has 350 pt available. Two
    // complete image/title/body cards must share it even as their copy grows.
    for text in [detail, String(repeating: detail, count: 5)] {
      let measured = try imageFrames(source(count: 2, detail: text), width: 350)
      let first = try XCTUnwrap(measured["a"]), second = try XCTUnwrap(measured["b"])
      XCTAssertEqual(first.width, 169 - 2 * clearInset, accuracy: 1)
      XCTAssertEqual(second.width, 169 - 2 * clearInset, accuracy: 1)
      XCTAssertEqual(first.minY, second.minY, accuracy: 1,
        "Long titles and body copy must wrap inside the two allocated columns")
      XCTAssertEqual(second.minX - first.maxX - 2 * clearInset, 12, accuracy: 1)
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

  @MainActor func testImagesWaitForUnknownRowContributorsThenStayFixedWhileCopyGrows() throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    var registry = library.registry
    let original = try XCTUnwrap(registry["Image"])
    let measured = ObjectCardFrames()
    let mount = ObjectCardMountLog()
    registry["Image"] = { element, registry in
      AnyView(original(element, registry).background(GeometryReader { geometry in
        Color.clear.onAppear { measured.values[PropValue.string(element, "alt") ?? ""] = geometry.frame(in: .global) }
          .onChange(of: geometry.frame(in: .global)) { measured.values[PropValue.string(element, "alt") ?? ""] = $0 }
      }).background {
        if PropValue.string(element, "alt") == "a" { ObjectCardMountMarker(log: mount) }
      })
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
    let clearInset = OpenUIThemeValues.defaults.spaceL + OpenUIPresentation.defaults.borderWidth
    XCTAssertEqual(before.width, 169 - 2 * clearInset, accuracy: 1)
    XCTAssertEqual(before.height, before.width * 9 / 16, accuracy: 1,
      "An unknown source reserves the cover slot inside its allocated column")
    let firstView = try XCTUnwrap(mount.view), mountCount = mount.created
    state.push(" copy that grows across many lines inside the same reading column.")
    settle()
    XCTAssertEqual(try XCTUnwrap(measured.values["a"]).width, before.width, accuracy: 1)
    XCTAssertEqual(try XCTUnwrap(measured.values["a"]).height, before.height, accuracy: 1)
    state.push("\")"); state.complete(); settle()
    XCTAssertEqual(try XCTUnwrap(measured.values["a"]).width, before.width, accuracy: 1)
    XCTAssertTrue(mount.view === firstView)
    XCTAssertEqual(mount.created, mountCount)

    // Layout fields can change through a component-local update after the
    // document completes. Surface padding changes within the same allocated
    // columns; the removed 160/240 pt policy must not force a different row.
    let sourceRevision = state.sourceRevision, presentationRevision = state.presentationRevision
    state.setFieldValue(form: "draft", name: "note", value: .string("Keep this edit"))
    settle()
    let theme = OpenUIThemeValues.defaults
    for surface in ["card", "sunk", "clear"] {
      state.setState("$surface", value: .string(OpenUIString(surface))); settle()
      XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
      let inset = OpenUIPresentation.defaults.borderWidth + (surface == "card" ? 0 : theme.spaceL)
      let expectedWidth = 169 - 2 * inset
      let first = try XCTUnwrap(measured.values["a"]), second = try XCTUnwrap(measured.values["b"])
      XCTAssertEqual(first.width, expectedWidth, accuracy: 1)
      XCTAssertEqual(second.width, expectedWidth, accuracy: 1)
      XCTAssertEqual(first.height, first.width * 9 / 16, accuracy: 1,
        "A standard Card gives the first image the same content box as its body")
      XCTAssertEqual(first.minY, second.minY, accuracy: 1)
      XCTAssertEqual(second.minX - first.maxX - 2 * inset, 12, accuracy: 1)
      XCTAssertTrue(mount.view === firstView, "Surface changes keep the existing mounted image")
      XCTAssertEqual(mount.created, mountCount)
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

@MainActor private final class ObjectCardMountLog {
  var view: NSView?
  var created = 0
}

private struct ObjectCardMountMarker: NSViewRepresentable {
  let log: ObjectCardMountLog
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    log.view = view; log.created += 1
    return view
  }
  func updateNSView(_ view: NSView, context: Context) {}
}
#endif
