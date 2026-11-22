import SwiftLang
import SwiftUI
import XCTest
@testable import SwiftOpenUI
#if os(macOS)
import AppKit
#endif

final class VisualPolishTests: XCTestCase {
  func testKnownTextRolesPreserveCompleteHostFontsAcrossRenderingAndMeasurement() {
    var theme = OpenUIThemeValues()
    theme.textBodySm = OpenUIFont(size: 23, weight: .light, family: "Custom", design: .serif,
      lineSpacing: 0.7, letterSpacing: 0.03).monospacedDigit()
    theme.textBodySmHeavy.weight = .black
    theme.textNeutralPrimary = .red
    theme.textNeutralSecondary = .blue
    let primary = theme.textStyle(.compactBody)
    let detail = theme.textStyle(.supporting)
    XCTAssertEqual(detail.font, theme.textBodySm)
    XCTAssertEqual(primary.font, detail.font)
    XCTAssertEqual(primary.color, .red)
    XCTAssertEqual(detail.color, .blue)
    XCTAssertEqual(detail.richText().font, detail.font)
    XCTAssertEqual(detail.richText().emphasisWeight, .black)
    XCTAssertEqual(detail.font.measuredLineHeight(scale: 2), theme.textBodySm.measuredLineHeight(scale: 2))
    theme.textBodySm.lineHeight = 2.2
    XCTAssertEqual(theme.textStyle(.supporting).font, theme.textBodySm,
      "Explicit leading and the whole host font survive role selection")
  }

  #if os(macOS)
  @MainActor private func height(_ source: String, width: CGFloat,
                                presentation: OpenUIPresentation = .init()) throws -> CGFloat {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource(source)
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    return NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
      .openUIPresentation(presentation).dynamicTypeSize(.large).frame(width: width)).fittingSize.height
  }

  @MainActor func testRenderedThumbnailAdaptsLocallyButAuthoredSizesRemainExact() throws {
    let automatic = "root=ImageText(\"\",\"Object\",\"Object\",null,true,\"horizontal\")"
    XCTAssertEqual(try height(automatic, width: 296), 80, accuracy: 1)
    XCTAssertEqual(try height(automatic, width: 216), 64, accuracy: 1)
    let fixed = "root=ImageText(\"\",\"Object\",\"Object\",null,true,\"horizontal\",112)"
    for width: CGFloat in [216, 296] {
      XCTAssertEqual(try height(fixed, width: width), 112, accuracy: 1,
        "Narrow cards do not rewrite an explicit imageSize")
    }
    var custom = OpenUIPresentation()
    custom.inlineThumbnailSize = 104
    XCTAssertEqual(try height(automatic, width: 360, presentation: custom), 104, accuracy: 1)
  }

  private struct Raster {
    let width: Int
    let height: Int
    let pixels: Data
    func count(_ matches: (UInt8, UInt8, UInt8) -> Bool) -> Int {
      stride(from: 0, to: pixels.count, by: 4).filter { matches(pixels[$0], pixels[$0 + 1], pixels[$0 + 2]) }.count
    }
  }

  @MainActor private func raster(_ source: String, theme: OpenUITheme = .init(),
                                 presentation: OpenUIPresentation = .init(), width: CGFloat = 320) throws -> Raster {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource(source)
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
      .openUITheme(theme).openUIPresentation(presentation).dynamicTypeSize(.large).frame(width: width).padding(12).background(Color.white)
      .environment(\.colorScheme, .light))
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = host
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
    defer { window.close() }
    // Mount the real presentation: an unmounted renderer intentionally disables
    // fields and therefore paints the disabled boundary, not the editable one.
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.08))
    window.setContentSize(host.fittingSize)
    host.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let image = try XCTUnwrap(bitmap.cgImage)
    let canvas = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
      bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    canvas.setFillColor(CGColor(gray: 1, alpha: 1))
    canvas.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    canvas.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return Raster(width: image.width, height: image.height,
      pixels: Data(bytes: try XCTUnwrap(canvas.data), count: image.width * image.height * 4))
  }

  @MainActor func testSunkPaintsNoGroupingBorderWhileItsInputBoundaryRemainsVisible() throws {
    var theme = OpenUITheme()
    // Use fixed RGB primaries, not adaptive system red/blue swatches, so this
    // checks visible boundaries rather than platform color-space hue choices.
    theme.borderDefault = Color(red: 1, green: 0, blue: 0)
    theme.borderInteractive = Color(red: 0, green: 0, blue: 1)
    theme.interactiveAccentDefault = Color(red: 0, green: 0, blue: 1)
    let red: (UInt8, UInt8, UInt8) -> Bool = { $0 > 180 && $1 < 100 && $2 < 100 }
    let blue: (UInt8, UInt8, UInt8) -> Bool = { $2 > 180 && $0 < 100 && $1 < 100 }
    for body in ["Card([TextContent(\"Note\")],VARIANT)", "MarkDownRenderer(\"Note\",VARIANT)"] {
      let sunk = try raster("root=" + body.replacingOccurrences(of: "VARIANT", with: "\"sunk\""), theme: theme)
      let card = try raster("root=" + body.replacingOccurrences(of: "VARIANT", with: "\"card\""), theme: theme)
      XCTAssertEqual(sunk.count(red), 0)
      XCTAssertGreaterThan(card.count(red), 100, "The normal card is the visible-border positive control")
    }
    let form = "Form(\"f\",Buttons([]),[FormControl(\"Field\",Input(\"x\",\"Value\"))])"
    let nested = try raster("root=Card([\(form)],\"sunk\")", theme: theme)
    XCTAssertEqual(nested.count(red), 0)
    XCTAssertGreaterThan(nested.count(blue), 50, "Removing the content border must not erase editable field boundaries")
  }

  @MainActor func testFormIsUnframedByDefaultAndSharesCardAppearanceWhenRequested() throws {
    var theme = OpenUITheme()
    let panelFill = Color(red: 0, green: 1, blue: 0)
    theme.foreground = panelFill
    theme.borderDefault = Color(red: 1, green: 0, blue: 0)
    theme.borderInteractive = Color(red: 0, green: 0, blue: 1)
    let form = "Form(\"f\",Buttons([]),[FormControl(\"Field\",Input(\"x\",\"Value\"))])"
    var framed = OpenUIPresentation()
    framed.formShowsCardSurface = true
    let panel = try raster("root=" + form, theme: theme, presentation: framed)
    let cardSource = "root=Card([\(form)])"
    let composed = try raster(cardSource, theme: theme)
    XCTAssertEqual(panel.width, composed.width)
    XCTAssertEqual(panel.height, composed.height)
    let unframed = try raster("root=" + form, theme: theme)
    let red: (UInt8, UInt8, UInt8) -> Bool = { $0 > 180 && $1 < 100 && $2 < 100 }
    let blue: (UInt8, UInt8, UInt8) -> Bool = { $0 < 100 && $1 < 100 && $2 > 180 }
    let green: (UInt8, UInt8, UInt8) -> Bool = { $0 < 100 && $1 > 180 && $2 < 100 }
    XCTAssertGreaterThan(panel.count(red), 100)
    XCTAssertEqual(composed.count(red), panel.count(red), "A Card around a Form paints one outline")
    XCTAssertEqual(panel.count(green), composed.count(green), "An opt-in Form uses the same transparent fill as Card")
    XCTAssertEqual(composed.count(green), unframed.count(green), "The outline adds no fill around the form")
    XCTAssertEqual(unframed.count(red), 0)
    XCTAssertGreaterThan(unframed.count(blue), 50, "A quiet Form must preserve editable field boundaries")
    XCTAssertGreaterThan(panel.height, unframed.height)
    var customized = OpenUIPresentation()
    customized.cardBackgroundColor = panelFill
    customized.cardBorderColor = Color(red: 1, green: 0, blue: 1)
    customized.borderWidth = 3
    let tinted = try raster(cardSource, theme: theme, presentation: customized)
    XCTAssertGreaterThan(tinted.count(green), composed.count(green), "The host can fill the standard Card")
    let magenta: (UInt8, UInt8, UInt8) -> Bool = { $0 > 180 && $1 < 100 && $2 > 180 }
    XCTAssertGreaterThan(tinted.count(magenta), 100, "The host can supply its own outline color")
    customized.formShowsCardSurface = true
    let tintedForm = try raster("root=" + form, theme: theme, presentation: customized)
    XCTAssertEqual(tintedForm.count(green), tinted.count(green))
    XCTAssertEqual(tintedForm.count(magenta), tinted.count(magenta))
  }

  @MainActor func testSingleLineFieldsUsePillCornersAndTextAreasUseThemeCorners() {
    var theme = OpenUIThemeValues()
    theme.radiusL = 4
    let bounds = CGRect(x: 0, y: 0, width: 180, height: 44)
    let field = NativeFieldSurface(theme: theme).shape.path(in: bounds)
    let editor = NativeFieldSurface(theme: theme, textEditor: true).shape.path(in: bounds)
    let nearCorner = CGPoint(x: 2, y: 5)

    XCTAssertFalse(field.contains(nearCorner))
    XCTAssertTrue(editor.contains(nearCorner))
    XCTAssertTrue(field.contains(CGPoint(x: 90, y: 5)))
  }

  @MainActor func testImageGallerySpacingIsIndependentOfTheBorderWidth() throws {
    let source = #"root=Stack([ImageGallery([{src:""}, {src:""}])])"#
    var presentation = OpenUIPresentation()
    XCTAssertEqual(presentation.imageGallerySpacing, 1)
    let defaultGallery = try raster(source, presentation: presentation)
    presentation.borderWidth = 8
    let thickerBorder = try raster(source, presentation: presentation)
    XCTAssertEqual(thickerBorder.height, defaultGallery.height)
    presentation.imageGallerySpacing = 16
    let spacedGallery = try raster(source, presentation: presentation)
    XCTAssertEqual(spacedGallery.width, defaultGallery.width)
    XCTAssertLessThan(spacedGallery.height, defaultGallery.height, "Two square tiles become smaller when a gap divides their width")
  }

  @MainActor func testNeutralIconAliasesRenderIdenticallyAndStatusVariantsKeepTheSameGeometry() throws {
    func source(_ variant: String) -> String {
      "root=IconText(Icon(\"map-pin\"),\"\(variant)\",\"m\",\"Same title\",\"Same details\",true)"
    }
    let neutral = try raster(source("neutral"))
    for variant in ["filled", "soft"] {
      let alias = try raster(source(variant))
      XCTAssertEqual(alias.width, neutral.width)
      XCTAssertEqual(alias.height, neutral.height)
      XCTAssertEqual(alias.pixels, neutral.pixels, "Aliases must not shift copy or add a different plate")
    }
    for variant in ["info", "success", "warning", "danger", "inverted"] {
      let status = try raster(source(variant))
      XCTAssertEqual(status.width, neutral.width)
      XCTAssertEqual(status.height, neutral.height)
    }
    let inverted = NativeIconTextStyle(variant: "inverted", theme: .init())
    XCTAssertNotEqual(inverted.background, .clear, "Inverted glyphs keep their contrasting surface")
  }

  /// Measure the painted surface independently of the invisible hit target.
  /// A 44pt target reproduces iOS's sizing feedback in the mounted macOS renderer.
  @MainActor func testButtonPaintDoesNotGrowWhenWrappedInRowOrColumn() throws {
    var presentation = OpenUIPresentation()
    presentation.minimumControlTargetSize = 44
    var theme = OpenUITheme()
    theme.interactiveAccentDefault = Color(red: 0, green: 0, blue: 1)
    theme.interactiveAccentDisabled = Color(red: 0, green: 0, blue: 1)
    func bounds(_ source: String, width: CGFloat = 320) throws -> CGRect {
      let image = try raster(source, theme: theme, presentation: presentation, width: width)
      var minX = image.width, minY = image.height, maxX = -1, maxY = -1
      for y in 0..<image.height {
        for x in 0..<image.width {
          let i = (y * image.width + x) * 4
          if image.pixels[i] < 50 && image.pixels[i + 1] < 80 && image.pixels[i + 2] > 180 {
            minX = min(minX, x); minY = min(minY, y)
            maxX = max(maxX, x); maxY = max(maxY, y)
          }
        }
      }
      XCTAssertGreaterThan(maxX, minX)
      return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
    for size in ["extra-small", "small", "medium", "large"] {
      let button = "Button(\"Details\",@OpenUrl(\"https://example.com\"),\"primary\",\"normal\",\"\(size)\")"
      let direct = try bounds("root=" + button)
      let row = try bounds("root=Buttons([\(button)],\"row\")")
      let column = try bounds("root=Buttons([\(button)],\"column\")")
      XCTAssertEqual(row.height, direct.height, accuracy: 1, "\(size): row must not paint its hit-target height")
      XCTAssertEqual(column.height, direct.height, accuracy: 1, "\(size): width fill must not change height")
      XCTAssertGreaterThan(column.width, direct.width + 40, "Column buttons still fill available width")
      XCTAssertGreaterThanOrEqual(try height("root=" + button, width: 320, presentation: presentation), 44)
    }
    let short = "Button(\"Details\",@OpenUrl(\"https://example.com\"),\"primary\",\"normal\",\"small\")"
    let long = "Button(\"Read the full details before continuing to the next step\",@OpenUrl(\"https://example.com\"),\"primary\",\"normal\",\"small\")"
    // Only the first surface is blue; the taller peer uses the destructive palette.
    let tallerPeer = "Button(\"Continue\\nnext step\",@OpenUrl(\"https://example.com\"),\"primary\",\"destructive\",\"large\")"
    XCTAssertEqual(try bounds("root=Buttons([\(short),\(tallerPeer)],\"row\")").height,
      try bounds("root=" + short).height, accuracy: 1,
      "A mixed-size, multiline peer must not enlarge the short button's painted surface")
    let directLong = try bounds("root=" + long, width: 140)
    XCTAssertGreaterThan(directLong.height, try bounds("root=" + short, width: 140).height)
    XCTAssertEqual(try bounds("root=Buttons([\(long)],\"row\")", width: 140).height,
      directLong.height, accuracy: 1, "Long text grows naturally rather than being clipped to a fixed height")
  }

  @MainActor func testMetadataTagsStayLighterThanActionsAndLongLabelsRemainUnbounded() throws {
    let tag = try height("root=Tag(\"Details\",null,\"md\",\"neutral\")", width: 240)
    let action = try height("root=Button(\"Details\",null,\"secondary\",\"normal\",\"medium\")", width: 240)
    XCTAssertLessThan(tag, action - 3)
    let long = String(repeating: "完整信息标签 ", count: 10)
    XCTAssertGreaterThan(try height("root=Tag(\(jsonStringLiteral(long)),null,\"md\",\"neutral\")", width: 180), tag * 2)
    let followup = try height("root=FollowUpBlock([FollowUpItem(\"Continue\")])", width: 240)
    XCTAssertGreaterThanOrEqual(followup, OpenUIPresentation().minimumControlTargetSize)
  }

  @MainActor func testUnavailableAndLoadedMediaKeepTheSameFrameIncludingLargeText() {
    _ = NSApplication.shared
    for size in [DynamicTypeSize.large, .accessibility2] {
      for width: CGFloat in [180, 320] {
        func dimensions(_ cached: Image?, sourceReady: Bool = true) -> CGSize {
          NSHostingView(rootView: NativeRemoteImage(src: nil, alt: "Object", layout: .aspect(16 / 9), cachedImage: cached)
            .environment(\.openUIMediaSourceReady, sourceReady).dynamicTypeSize(size)
            .frame(width: width)).fittingSize
        }
        let empty = dimensions(nil)
        XCTAssertEqual(empty.width, width, accuracy: 1)
        XCTAssertEqual(empty.height, width * 9 / 16, accuracy: 1)
        XCTAssertEqual(dimensions(Image(systemName: "photo")), empty)
        XCTAssertEqual(dimensions(nil, sourceReady: false), empty)
      }
    }
  }

  @MainActor private func artworkRoot<Content: View>(_ view: Content, width: CGFloat) -> AnyView {
    // accessibilityReduceMotion is read-only on supported Apple SDKs. These
    // snapshots assert the final artwork, not the operating system preference.
    var presentation = OpenUIPresentation()
    presentation.motion.mediaRevealDuration = 0
    presentation.motion.loadingIndicatorDelay = 60
    return AnyView(view.openUIPresentation(presentation)
      .transaction { $0.animation = nil; $0.disablesAnimations = true }
      .frame(width: width).background(Color.white))
  }

  @MainActor private func artworkHost<Content: View>(_ view: Content, size: CGSize = CGSize(width: 72, height: 72)) -> (NSHostingView<AnyView>, NSWindow) {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: artworkRoot(view, width: size.width))
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)
    window.contentView = host
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderFront(nil)
    host.layoutSubtreeIfNeeded()
    return (host, window)
  }

  @MainActor private func artworkPixels(_ host: NSHostingView<AnyView>, name: String) throws -> Raster {
    host.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let image = try XCTUnwrap(bitmap.cgImage)
    let canvas = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
      bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    canvas.setFillColor(CGColor(gray: 1, alpha: 1))
    canvas.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    canvas.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    if let directory = ProcessInfo.processInfo.environment["OPENUI_SNAPSHOT_DIR"] {
      try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }
    return Raster(width: image.width, height: image.height,
      pixels: Data(bytes: try XCTUnwrap(canvas.data), count: image.width * image.height * 4))
  }

  @MainActor func testMissingMapArtworkIsAPOISymbolNotABlankPhoto() throws {
    var theme = OpenUITheme()
    theme.interactiveAccentDefault = Color(red: 0, green: 0, blue: 1)
    theme.foreground = Color(red: 1, green: 0, blue: 0)
    for direction in [LayoutDirection.leftToRight, .rightToLeft] {
      for scheme in [ColorScheme.light, .dark] {
        let (host, window) = artworkHost(NativeMapPlaceArtwork(source: nil, title: "地点", side: 72)
          .openUITheme(theme)
          .environment(\.layoutDirection, direction).environment(\.colorScheme, scheme))
        defer { window.close() }
        let image = try artworkPixels(host, name: "map-poi-\(direction)-\(scheme)")
        XCTAssertGreaterThan(image.count { r, g, b in min(r, g, b) < 180 }, 20,
          "A semantic location glyph must be visible, not merely an empty photo frame")
        XCTAssertEqual(image.count { r, g, b in r > 180 && g < 100 && b < 100 }, 0,
          "The POI glyph must not acquire a foreground-colored circular plate")
        for (x, y) in [(0.1, 0.1), (0.5, 0.1), (0.9, 0.9)] {
          let offset = (Int(Double(image.height) * y) * image.width + Int(Double(image.width) * x)) * 4
          XCTAssertGreaterThanOrEqual(image.pixels[offset], 250)
          XCTAssertGreaterThanOrEqual(image.pixels[offset + 1], 250)
          XCTAssertGreaterThanOrEqual(image.pixels[offset + 2], 250,
            "Outside the glyph, the thumbnail slot must expose the containing surface")
        }
        XCTAssertEqual(host.fittingSize.width, 72, accuracy: 1)
        XCTAssertEqual(host.fittingSize.height, 72, accuracy: 1)
      }
    }
  }

  @MainActor func testMissingOrdinaryArtworkKeepsThePhotoSymbolAndDeclaredGeometry() throws {
    var theme = OpenUITheme()
    theme.imagePlaceholderBackground = Color(red: 0, green: 1, blue: 0)
    let (host, window) = artworkHost(NativeRemoteImage(src: nil, alt: "描述", layout: .aspect(1.5)).openUITheme(theme),
      size: CGSize(width: 180, height: 120))
    defer { window.close() }
    let image = try artworkPixels(host, name: "media-missing-placeholder")
    let fillCount = image.count { r, g, b in
      r == image.pixels[0] && g == image.pixels[1] && b == image.pixels[2]
    }
    let fill = image.pixels.prefix(3)
    let centerHasSymbol = (image.height / 3..<image.height * 2 / 3).contains { y in
      (image.width / 3..<image.width * 2 / 3).contains { x in
        let offset = (y * image.width + x) * 4
        return !image.pixels[offset..<(offset + 3)].elementsEqual(fill)
      }
    }
    XCTAssertGreaterThan(fillCount, image.width * image.height * 98 / 100)
    XCTAssertTrue(centerHasSymbol, "The centered photo symbol remains visible")
    XCTAssertEqual(host.fittingSize.width, 180, accuracy: 1)
    XCTAssertEqual(host.fittingSize.height, 120, accuracy: 1)
  }

  @MainActor func testFailedPhotoKeepsLoadingFillWithoutRefetchingOnFitting() async throws {
    let loader = ArtworkFailureLoader()
    let loading = expectation(description: "loading presented")
    let unavailable = expectation(description: "failure presented")
    var sawLoading = false, sawFailure = false
    let (host, window) = artworkHost(NativeRemoteImage(src: "https://artwork.test/fail", alt: "描述", layout: .aspect(1.5),
      onStatus: { status, _ in
        if status == .loading && !sawLoading { sawLoading = true; loading.fulfill() }
        if status == .unavailable && !sawFailure { sawFailure = true; unavailable.fulfill() }
      }).openUIResourceContext(.init(loader: loader)), size: CGSize(width: 180, height: 120))
    defer { window.close(); Task { await loader.releaseFailure() } }
    await fulfillment(of: [loading], timeout: 3)
    let before = host.fittingSize
    let waiting = try artworkPixels(host, name: "media-before-failure")
    await loader.releaseFailure()
    await fulfillment(of: [unavailable], timeout: 3)
    let image = try artworkPixels(host, name: "media-failed-placeholder")
    XCTAssertEqual(image.pixels, waiting.pixels, "Failure keeps the loading placeholder fill")
    XCTAssertEqual(host.fittingSize, before, "A failure must not move neighboring text")
    for _ in 0..<20 { _ = host.fittingSize; host.layoutSubtreeIfNeeded() }
    XCTAssertEqual(loader.calls, 1)
  }

  @MainActor func testFailedPhotoCanBeRetriedByClickingItsPlaceholder() async throws {
    let loader = ArtworkFailureLoader(succeedsOnRetry: true)
    let unavailable = expectation(description: "first image request failed")
    let loaded = expectation(description: "manual retry loaded the image")
    var sawFailure = false, sawSuccess = false
    let (host, window) = artworkHost(NativeRemoteImage(src: "https://artwork.test/retry", alt: "描述",
      layout: .aspect(1.5), onStatus: { status, _ in
        if status == .unavailable && !sawFailure { sawFailure = true; unavailable.fulfill() }
        if status == .loaded && !sawSuccess { sawSuccess = true; loaded.fulfill() }
      }).openUIResourceContext(.init(loader: loader)), size: CGSize(width: 180, height: 120))
    defer { window.close(); Task { await loader.releaseFailure() } }
    await loader.releaseFailure()
    await fulfillment(of: [unavailable], timeout: 3)
    let before = host.fittingSize
    let failureImage = try artworkPixels(host, name: "media-before-manual-retry")
    for _ in 0..<20 { _ = host.fittingSize; host.layoutSubtreeIfNeeded() }
    XCTAssertEqual(loader.calls, 1, "Only a user retry may start the next request")

    try clickArtworkCenter(host, window: window)
    await fulfillment(of: [loaded], timeout: 3)
    let recoveredImage = try artworkPixels(host, name: "media-after-manual-retry")
    XCTAssertNotEqual(recoveredImage.pixels, failureImage.pixels)
    XCTAssertEqual(host.fittingSize, before, "Retry must retain the declared image slot")
    XCTAssertEqual(loader.calls, 2, "One click must cause exactly one retry of the same source")
    XCTAssertEqual(loader.lastCachePolicy, .reloadIgnoringLocalCacheData)
    for _ in 0..<20 { _ = host.fittingSize; host.layoutSubtreeIfNeeded() }
    XCTAssertEqual(loader.calls, 2, "Rendering the recovered image must not fetch it again")
  }

  @MainActor private func clickArtworkCenter(_ host: NSHostingView<AnyView>, window: NSWindow) throws {
    // Use the existing offscreen AppKit event path, not a direct call to the
    // retry closure: this also checks that the failed image remains hittable.
    host.layoutSubtreeIfNeeded()
    let point = host.convert(NSPoint(x: host.bounds.midX, y: host.bounds.midY), to: nil)
    let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
      modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point,
      modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime + 0.01,
      windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
    NSApplication.shared.postEvent(up, atStart: false)
    window.sendEvent(down)
    window.sendEvent(up)
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    host.layoutSubtreeIfNeeded()
  }

  @MainActor func testImageFailureKeepsThemedPlaceholderAndRetriesInItsOriginalSlot() async throws {
    let loader = ArtworkFailureLoader(succeedsOnRetry: true)
    var theme = OpenUITheme()
    theme.sunk = .red
    theme.imagePlaceholderBackground = Color(red: 0.2, green: 0.5, blue: 0.9)
    theme.textNeutralSecondary = .black
    let loading = expectation(description: "content image loading")
    let unavailable = expectation(description: "content image unavailable")
    let loaded = expectation(description: "content placeholder retry loaded")
    var sawLoading = false, sawFailure = false, sawSuccess = false
    func content(alt: String) -> some View {
      NativeRemoteImage(src: "https://artwork.test/fail", alt: alt, layout: .aspect(1.5),
        onStatus: { status, _ in
          if status == .loading && !sawLoading { sawLoading = true; loading.fulfill() }
          if status == .unavailable && !sawFailure { sawFailure = true; unavailable.fulfill() }
          if status == .loaded && !sawSuccess { sawSuccess = true; loaded.fulfill() }
        }).openUIResourceContext(.init(loader: loader))
        .openUITheme(theme).environment(\.colorScheme, .light)
    }
    let (host, window) = artworkHost(content(alt: "这张内容图片展示完整的交通换乘说明。"),
      size: CGSize(width: 240, height: 160))
    defer { window.close(); Task { await loader.releaseFailure() } }
    await fulfillment(of: [loading], timeout: 3)
    let before = host.fittingSize
    let loadingImage = try artworkPixels(host, name: "content-image-loading-placeholder")
    XCTAssertGreaterThan(loadingImage.count { r, _, b in r < 95 && b > 175 },
      loadingImage.width * loadingImage.height * 98 / 100)
    await loader.releaseFailure()
    await fulfillment(of: [unavailable], timeout: 3)
    let image = try artworkPixels(host, name: "content-image-failed-placeholder")
    XCTAssertEqual(image.pixels, loadingImage.pixels, "Failure retains the themed fill and photo symbol without adding status copy")
    XCTAssertEqual(host.fittingSize, before, "A resource failure cannot move adjacent content")
    host.rootView = artworkRoot(content(alt: "A different, much longer alternative description remains available to VoiceOver."), width: 240)
    try await Task.sleep(nanoseconds: 100_000_000)
    let updated = try artworkPixels(host, name: "content-image-alternative-accessibility-only")
    XCTAssertEqual(updated.pixels, image.pixels, "Alternative copy must not turn into a visible failure paragraph")
    for _ in 0..<20 { _ = host.fittingSize; host.layoutSubtreeIfNeeded() }
    XCTAssertEqual(loader.calls, 1, "Re-measuring a recovery control must not retry the resource")
    try clickArtworkCenter(host, window: window)
    await fulfillment(of: [loaded], timeout: 3)
    XCTAssertEqual(loader.calls, 2, "Clicking the placeholder makes exactly one retry")
    XCTAssertEqual(loader.lastCachePolicy, .reloadIgnoringLocalCacheData)
    XCTAssertEqual(host.fittingSize, before)
  }

  @MainActor func testSemanticArtworkIsIdenticalWhileLoadingAndAfterFailure() async throws {
    let loader = ArtworkFailureLoader()
    let loading = expectation(description: "symbol while loading")
    let unavailable = expectation(description: "symbol after failure")
    var sawLoading = false, sawFailure = false
    let (host, window) = artworkHost(NativeRemoteImage(src: "https://artwork.test/fail", alt: "地点",
      layout: .thumbnail(CGSize(width: 72, height: 72)), fallbackSystemImage: "mappin.and.ellipse",
      onStatus: { status, _ in
        if status == .loading && !sawLoading { sawLoading = true; loading.fulfill() }
        if status == .unavailable && !sawFailure { sawFailure = true; unavailable.fulfill() }
      }).openUIResourceContext(.init(loader: loader)))
    defer { window.close(); Task { await loader.releaseFailure() } }
    await fulfillment(of: [loading], timeout: 3)
    let before = try artworkPixels(host, name: "map-poi-loading")
    XCTAssertGreaterThan(before.count { r, g, b in min(r, g, b) < 180 }, 20)
    await loader.releaseFailure()
    await fulfillment(of: [unavailable], timeout: 3)
    let after = try artworkPixels(host, name: "map-poi-failed")
    XCTAssertEqual(after.pixels, before.pixels, "Failure does not replace the place glyph with an error tile")
  }

  @MainActor func testPhotoCanRecoverWhenTheSourceChangesAfterFailure() async throws {
    let loader = ArtworkFailureLoader()
    let failed = expectation(description: "initial request failed")
    let loaded = expectation(description: "replacement image loaded")
    var sawFailure = false, sawSuccess = false
    func content(_ path: String) -> some View {
      NativeRemoteImage(src: "https://artwork.test/" + path, alt: "地点",
        layout: .thumbnail(CGSize(width: 72, height: 72)), fallbackSystemImage: "mappin.and.ellipse",
        onStatus: { status, _ in
          if status == .unavailable && !sawFailure { sawFailure = true; failed.fulfill() }
          if status == .loaded && !sawSuccess { sawSuccess = true; loaded.fulfill() }
        }).openUIResourceContext(.init(loader: loader))
    }
    let (host, window) = artworkHost(content("fail"))
    defer { window.close(); Task { await loader.releaseFailure() } }
    await loader.releaseFailure()
    await fulfillment(of: [failed], timeout: 3)
    let before = try artworkPixels(host, name: "map-poi-before-recovery")
    host.rootView = artworkRoot(content("success"), width: 72)
    host.layoutSubtreeIfNeeded()
    await fulfillment(of: [loaded], timeout: 3)
    let after = try artworkPixels(host, name: "map-photo-after-recovery")
    XCTAssertNotEqual(after.pixels, before.pixels)
    XCTAssertEqual(host.fittingSize, CGSize(width: 72, height: 72))
    XCTAssertEqual(loader.calls, 2, "A failed source cannot suppress a later valid image")
  }
  #endif
}

#if os(macOS)
/// A gated, in-memory failure keeps tests independent of networking and timing.
private final class ArtworkFailureLoader: OpenUIResourceLoading {
  private actor Gate {
    var resolved = false
    var waiters: [CheckedContinuation<Data, Error>] = []
    func wait() async throws -> Data {
      try await withCheckedThrowingContinuation { continuation in
        if resolved { continuation.resume(throwing: URLError(.cannotLoadFromNetwork)) }
        else { waiters.append(continuation) }
      }
    }
    func release() {
      resolved = true
      let current = waiters; waiters.removeAll()
      for waiter in current { waiter.resume(throwing: URLError(.cannotLoadFromNetwork)) }
    }
  }
  private let gate = Gate()
  private let lock = NSLock()
  private let succeedsOnRetry: Bool
  private var count = 0
  private var cachePolicy: URLRequest.CachePolicy?
  init(succeedsOnRetry: Bool = false) { self.succeedsOnRetry = succeedsOnRetry }
  var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
  var lastCachePolicy: URLRequest.CachePolicy? { lock.lock(); defer { lock.unlock() }; return cachePolicy }
  private func record(_ request: URLRequest) -> Int {
    lock.lock(); defer { lock.unlock() }
    count += 1; cachePolicy = request.cachePolicy
    return count
  }
  func request(for source: String, relativeTo baseURL: URL?) -> URLRequest? {
    OpenUIURLSessionResourceLoader.shared.request(for: source, relativeTo: baseURL)
  }
  func data(for request: URLRequest) async throws -> Data {
    let attempt = record(request)
    if request.url?.lastPathComponent == "success" || (succeedsOnRetry && attempt > 1) {
      return Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=")!
    }
    return try await withTaskCancellationHandler(operation: { try await gate.wait() },
      onCancel: { Task { await self.gate.release() } })
  }
  func releaseFailure() async { await gate.release() }
}
#endif
