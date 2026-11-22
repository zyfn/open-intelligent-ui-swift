import SwiftLang
import SwiftUI
import XCTest
@testable import SwiftOpenUI
#if os(macOS)
import AppKit
#endif

final class StreamingLayoutContractTests: XCTestCase {
  private func libraryWithFlexiblePanel() throws -> OpenUIComponentLibrary {
    let card = try XCTUnwrap(OpenUIComponents.components.first { $0.definition.name == "Card" })
    let panel = card.replacingDefinition(defineComponent(name: "Panel", description: "The same flexible renderer",
      params: card.definition.params))
    return try OpenUIComponents.library().extending(adding: [panel])
  }

  @MainActor func testClosedLayoutCanStreamItsReferencedTextWithoutWaitingForWholeProgram() throws {
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.push("root=Stack([copy],\"column\",\"s\")\ncopy=TextContent(\"正在逐字")
    let root = try XCTUnwrap(state.root)
    XCTAssertFalse(root.isSourceComplete)
    XCTAssertTrue(NativeLayoutContract.ready(root.sourceReadiness, fields: library.registry.presentationLayoutFields("Stack")))
  }

  @MainActor func testReplacingAStandardRendererDoesNotInheritItsLayoutGate() throws {
    let library = try OpenUIComponents.library()
    var registry = library.registry
    XCTAssertFalse(registry.presentationLayoutFields("Stack").isEmpty)
    registry["Stack"] = { _, _ in AnyView(Text("Custom")) }
    XCTAssertTrue(registry.presentationLayoutFields("Stack").isEmpty)
  }

  @MainActor func testRegisteredWidthContractAllowsStreamingUnderAnotherComponentName() throws {
    let library = try libraryWithFlexiblePanel()
    let state = OpenUIState(schema: library.library.toSchema())
    state.push("root=Stack([panel],\"row\",\"m\",\"start\",\"start\",true)\npanel=Panel([copy],\"clear\")\ncopy=TextContent(\"Still growing")
    let root = try XCTUnwrap(state.root)
    let panel = try XCTUnwrap(PropValue.children(root).first)
    XCTAssertFalse(panel.isSourceComplete)
    let context = OpenUIComponentContext(element: root, registry: library.registry, state: state)
    XCTAssertTrue(context.rowWidthReady,
      "Declared width independence must not depend on the component being named Card")

    var replacement = library.registry
    replacement["Panel"] = library.registry["Panel"]
    let replacedContext = OpenUIComponentContext(element: root, registry: replacement, state: state)
    XCTAssertFalse(replacedContext.rowWidthReady,
      "An unannotated replacement must wait for its potentially width-changing content")
    state.push("\")"); state.complete()
    let complete = OpenUIComponentContext(element: try XCTUnwrap(state.root), registry: replacement, state: state)
    XCTAssertTrue(complete.rowWidthReady)
  }

  @MainActor func testChartDoesNotCommitItsDefaultHeightBeforeATrailingHeightArrives() throws {
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.push("root=LineChart([\"A\",\"B\"],[Series(\"S\",[1,2])],\"linear\",\"X\",\"Y\",")
    let fields = library.registry.presentationLayoutFields("LineChart")
    XCTAssertTrue(fields.contains("height"))
    XCTAssertFalse(NativeLayoutContract.ready(try XCTUnwrap(state.root).sourceReadiness, fields: fields))
    state.push("160)")
    XCTAssertTrue(NativeLayoutContract.ready(try XCTUnwrap(state.root).sourceReadiness, fields: fields))
  }

  #if os(macOS)
  @MainActor func testSourceOnlyTerminalFeedbackHasNoVisibleFooterOrReservedHeight() throws {
    _ = NSApplication.shared
    let quiet = NSHostingView(rootView: NativePendingContent(loading: false).frame(width: 320))
    XCTAssertLessThan(quiet.fittingSize.height, 1)
    let failure = NSHostingView(rootView: NativePendingContent(loading: false,
      terminalMessage: "Content unavailable").frame(width: 320))
    XCTAssertGreaterThan(failure.fittingSize.height, 10,
      "Removing source diagnostics must not suppress explicit data/resource failures")
  }

  @MainActor func testTerminalPartialStackKeepsReadablePrefixWithoutNarratingParserDiagnostics() throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    var registry = library.registry
    registry["TextContent"] = { _, _ in AnyView(Text("Visible prose")) }
    func height(_ source: String) throws -> CGFloat {
      let state = OpenUIState(schema: library.library.toSchema())
      state.setSource(source)
      XCTAssertNotNil(state.root)
      if source.hasSuffix("missing") {
        XCTAssertFalse(try XCTUnwrap(state.root).isSourceComplete,
          "Removing a diagnostic footer must not mark the underlying input as complete")
      }
      let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: registry).frame(width: 320))
      return host.fittingSize.height
    }
    let complete = try height(#"root=Stack([TextContent("Visible prose")])"#)
    let incomplete = #"root=Stack([TextContent("Visible prose"),missing"#
    let parser = createParser(schema: library.library.toSchema())
    XCTAssertTrue(parser.parse(incomplete).meta.incomplete, "Retain the original malformed source and its diagnostics")
    XCTAssertEqual(try height(incomplete), complete, accuracy: 1,
      "A terminal readable prefix must not append a generic Content is incomplete paragraph")
  }

  @MainActor func testCardVariantsShareColumnsUsingOnlyTheirDeclaredSurfaceInsets() throws {
    _ = NSApplication.shared
    let library = try libraryWithFlexiblePanel()
    let state = OpenUIState(schema: library.library.toSchema())
    var registry = library.registry
    let original = try XCTUnwrap(registry["Image"])
    var frames: [String: CGRect] = [:]
    registry["Image"] = { element, registry in
      let key = PropValue.string(element, "alt") ?? "?"
      return AnyView(original(element, registry).background(GeometryReader { geometry in
        Color.clear.onAppear { frames[key] = geometry.frame(in: .global) }
          .onChange(of: geometry.frame(in: .global)) { frames[key] = $0 }
      }))
    }
    var presentation = OpenUIPresentation()
    presentation.minimumTextColumnWidth = 1000
    presentation.minimumCardWidth = 2000
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: registry)
      .openUIPresentation(presentation).dynamicTypeSize(.accessibility3).frame(width: 320))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 320, height: 600),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    window.setFrameOrigin(.init(x: -10000, y: -10000)); window.orderFront(nil)
    defer { window.close() }
    func settle(_ source: String) {
      frames.removeAll(); state.setSource(source)
      host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.10))
      host.layoutSubtreeIfNeeded()
    }
    for name in ["Card", "Panel"] {
      for variant in ["clear", "card", "sunk"] {
        for count in [2, 3] {
          let children = (0..<count).map { "\(name)([Image(\"\($0)\",\"\")],\"\(variant)\")" }.joined(separator: ",")
          // Upstream Card uses flex:1/min-width:0. Large native reading-width
          // overrides and Dynamic Type must not add variant-specific breakpoints.
          for wrap in [false, true] {
            settle("root=Stack([\(children)],\"row\",\"m\",\"start\",\"start\",\(wrap))")
            // Upstream card.scss (7b7a519) gives card zero padding, clear
            // horizontal space-l, and sunk space-l on all sides. Every
            // variant's border participates in the outer box, even if clear.
            let theme = OpenUIThemeValues.defaults
            let inset = presentation.borderWidth + (variant == "card" ? 0 : theme.spaceL)
            let cell = (320 - CGFloat(count - 1) * 12) / CGFloat(count)
            let first = try XCTUnwrap(frames["0"])
            for index in 0..<count {
              let rect = try XCTUnwrap(frames[String(index)])
              XCTAssertEqual(rect.width, cell - 2 * inset, accuracy: 1,
                "\(name) \(variant), \(count) columns, wrap=\(wrap)")
              XCTAssertEqual(rect.minX, CGFloat(index) * (cell + 12) + inset, accuracy: 1)
              XCTAssertEqual(rect.height, rect.width * 9 / 16, accuracy: 1,
                "A standard Card does not enlarge its first image through negative insets")
              XCTAssertEqual(rect.minY, first.minY, accuracy: 1,
                "Only actual outer insets constrain these flexible items; all fit on this row")
            }
          }
        }
      }
    }
    settle("root=Card([Card([Image(\"nested\",\"\")],\"clear\")],\"clear\")")
    let clearInset = OpenUIThemeValues.defaults.spaceL + presentation.borderWidth
    let nested = try XCTUnwrap(frames["nested"])
    XCTAssertEqual(nested.width, 320 - 4 * clearInset, accuracy: 1,
      "Each explicit clear Card keeps its upstream horizontal padding and border, including nested cards")
    XCTAssertEqual(nested.minX, 2 * clearInset, accuracy: 1)
  }

  @MainActor func testStandardCardBorderAndPaddingApplyEquallyToLeadingAndBodyImages() throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let theme = OpenUIThemeValues.defaults
    // card.scss at upstream 7b7a519 defines a real border box and no special
    // first-image treatment. An explicit host border width keeps that geometry.
    for border in [CGFloat(1), 3] {
      for variant in ["card", "clear", "sunk"] {
        let state = OpenUIState(schema: library.library.toSchema())
        state.setSource("root=Card([Image(\"first\"),Image(\"body\")],\"\(variant)\",\"column\",\"m\")")
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        var registry = library.registry
        let original = try XCTUnwrap(registry["Image"])
        var frames: [String: CGRect] = [:]
        var outerFrame: CGRect?
        registry["Image"] = { element, registry in
          let key = PropValue.string(element, "alt") ?? "?"
          return AnyView(original(element, registry).background(GeometryReader { geometry in
            Color.clear.onAppear { frames[key] = geometry.frame(in: .named("standard-card")) }
              .onChange(of: geometry.frame(in: .named("standard-card"))) { frames[key] = $0 }
          }))
        }
        var presentation = OpenUIPresentation()
        presentation.borderWidth = border
        let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: registry)
          .openUIPresentation(presentation).frame(width: 320)
          .background(GeometryReader { geometry in
            Color.clear.onAppear { outerFrame = geometry.frame(in: .named("standard-card")) }
              .onChange(of: geometry.frame(in: .named("standard-card"))) { outerFrame = $0 }
          })
          .coordinateSpace(name: "standard-card").fixedSize(horizontal: false, vertical: true))
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 320, height: 700),
          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        window.setFrameOrigin(.init(x: -10000, y: -10000)); window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        host.layoutSubtreeIfNeeded()

        let outer = try XCTUnwrap(outerFrame)
        let first = try XCTUnwrap(frames["first"]), body = try XCTUnwrap(frames["body"])
        let horizontal = border + (variant == "card" ? 0 : theme.spaceL)
        let vertical = border + (variant == "sunk" ? theme.spaceL : 0)
        let imageWidth = 320 - 2 * horizontal
        let imageHeight = imageWidth * 9 / 16
        XCTAssertEqual(outer.width, 320, accuracy: 1)
        XCTAssertEqual(outer.height, 2 * vertical + 2 * imageHeight + theme.spaceM, accuracy: 1,
          "\(variant), border \(border): both padding and border occupy layout space")
        for image in [first, body] {
          XCTAssertEqual(image.minX - outer.minX, horizontal, accuracy: 1)
          XCTAssertEqual(image.width, imageWidth, accuracy: 1)
          XCTAssertEqual(image.height, imageHeight, accuracy: 1)
        }
        XCTAssertEqual(first.minY - outer.minY, vertical, accuracy: 1)
        XCTAssertEqual(body.minY - first.maxY, theme.spaceM, accuracy: 1)
        XCTAssertEqual(outer.maxY - body.maxY, vertical, accuracy: 1)
      }
    }
  }

  @MainActor func testLaterUnresolvedSiblingDoesNotRemoveOrRemountAnAlreadyVisibleText() throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    let log = LayoutTextMountLog()
    var registry = library.registry
    let original = try XCTUnwrap(registry["TextContent"])
    registry["TextContent"] = { element, registry in
      AnyView(original(element, registry).background {
        if PropValue.string(element, "text") == "Stable" { LayoutTextMountMarker(log: log) }
      })
    }
    state.push("root=Stack([TextContent(\"Stable\")")
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: registry).frame(width: 320))
    let window = NSWindow(contentRect: .init(x:0,y:0,width:320,height:700), styleMask:[.borderless], backing:.buffered, defer:false)
    window.isReleasedWhenClosed=false; window.contentView=host
    window.setFrameOrigin(.init(x:-10000,y:-10000)); window.orderFront(nil)
    defer { window.close() }
    func settle() { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until:Date().addingTimeInterval(0.10)) }
    settle()
    let first = try XCTUnwrap(log.view)
    state.push(",later")
    settle()
    XCTAssertEqual(log.removed, 0, "A later unresolved slot cannot erase the readable prefix")
    XCTAssertTrue(log.view === first)
    state.push("],\"column\",\"m\")\nlater=TextContent(\"Later\")")
    settle()
    XCTAssertTrue(log.view === first, "Settling layout must preserve the existing text view identity")
    XCTAssertEqual(log.created, 1)
    XCTAssertEqual(log.removed, 0)
  }

  @MainActor func testFluidMediaWaitsCompactlyButKnownThumbnailKeepsItsFixedSize() {
    _ = NSApplication.shared
    let fluid = NSHostingView(rootView: NativeRemoteImage(src: nil, layout: .cover,
      cachedImage: Image(systemName: "photo")).environment(\.openUIMediaWidthReady, false)
      .environment(\.openUIStreamActive, true).frame(width: 320))
    XCTAssertLessThan(fluid.fittingSize.height, 100)
    let resolved = NSHostingView(rootView: NativeRemoteImage(src: nil, layout: .cover,
      cachedImage: Image(systemName: "photo")).frame(width: 320))
    XCTAssertEqual(resolved.fittingSize.height, 180, accuracy: 1)
    let thumbnail = NSHostingView(rootView: NativeRemoteImage(src: nil,
      layout: .thumbnail(.init(width: 72, height: 72)), cachedImage: Image(systemName: "photo"))
      .environment(\.openUIMediaWidthReady, false))
    XCTAssertEqual(thumbnail.fittingSize, .init(width: 72, height: 72))
  }

  @MainActor func testLateWrapArgumentDoesNotRevealAnIntermediateTwoColumnImageLayout() throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    var registry = library.registry
    let original = try XCTUnwrap(registry["Image"])
    var sizes: [String: CGSize] = [:]
    registry["Image"] = { element, registry in
      let key = PropValue.string(element,"alt") ?? "?"
      return AnyView(original(element,registry).background(GeometryReader { g in
        Color.clear.onAppear { sizes[key] = g.size }.onChange(of: g.size) { sizes[key] = $0 }
      }))
    }
    let host = NSHostingView(rootView: OpenUIContentView(state: state,registry:registry).frame(width:320))
    let window = NSWindow(contentRect:.init(x:0,y:0,width:320,height:1000),styleMask:[.borderless],backing:.buffered,defer:false)
    window.isReleasedWhenClosed=false; window.contentView=host
    window.setFrameOrigin(.init(x:-10000,y:-10000)); window.orderFront(nil)
    defer { window.close() }
    state.push("root=Stack([pair])\na=Stack([Image(\"A\",\"\"),TextContent(\"第一块已经完整的内容\")])\nb=Stack([Image(\"B\",\"\"),TextContent(\"第二块已经完整并且较长的内容\")])\npair=Stack([a,")
    for chunk in ["b],", "\"row\",", "\"m\",\"start\",\"start\","] {
      state.push(chunk)
      host.layoutSubtreeIfNeeded(); RunLoop.main.run(until:Date().addingTimeInterval(0.06))
      XCTAssertTrue(sizes.isEmpty, "Do not reveal an image at a guessed intermediate width")
    }
    state.push("true)")
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until:Date().addingTimeInterval(0.06))
    XCTAssertNotNil(sizes["A"]); XCTAssertNotNil(sizes["B"])
    let committed = sizes
    state.complete()
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until:Date().addingTimeInterval(0.06))
    XCTAssertEqual(sizes, committed)
  }
  #endif
}

#if os(macOS)
@MainActor private final class LayoutTextMountLog {
  var view: NSView?
  var created = 0
  var removed = 0
}
private struct LayoutTextMountMarker: NSViewRepresentable {
  let log: LayoutTextMountLog
  func makeCoordinator() -> LayoutTextMountLog { log }
  func makeNSView(context: Context) -> NSView {
    let view = NSView(); log.view = view; log.created += 1; return view
  }
  func updateNSView(_ view: NSView, context: Context) {}
  static func dismantleNSView(_ view: NSView, coordinator: LayoutTextMountLog) { coordinator.removed += 1 }
}
#endif
