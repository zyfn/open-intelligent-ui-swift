#if os(macOS)
import AppKit
import SwiftUI
import SwiftLang
import XCTest
@testable import SwiftOpenUI

final class ImageLoadingBackgroundTests: XCTestCase {
  func testImageBackgroundOverridesComposeWithThemeScopes() {
    var common = OpenUITheme()
    common.imagePlaceholderBackground = .blue
    var appearance = OpenUITheme()
    appearance.sunk = .red
    let inherited = appearance.resolved(over: common.resolved())
    XCTAssertEqual(inherited.imagePlaceholderBackground, .blue)
    XCTAssertEqual(inherited.sunk, .red)

    appearance.imagePlaceholderBackground = .green
    XCTAssertEqual(appearance.resolved(over: common.resolved()).imagePlaceholderBackground, .green)
    var otherSurface = OpenUITheme()
    otherSurface.sunk = .red
    XCTAssertEqual(otherSurface.resolved().imagePlaceholderBackground, OpenUITheme().resolved().imagePlaceholderBackground)
  }

  @MainActor func testStreamingSVGUsesImageOverrideAndFailureKeepsSunk() throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.push("root=SVG(null,source,\"Diagram\")\nsource=\"https://assets.test/incomplete.svg")
    XCTAssertNotNil(state.root)
    var overrides = OpenUITheme()
    overrides.sunk = .red
    overrides.imagePlaceholderBackground = .blue
    let host = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
      .openUITheme(overrides).environment(\.colorScheme, .light).frame(width: 200))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 112),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.appearance = NSAppearance(named: .aqua)
    window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
    window.orderFront(nil)
    defer { window.close() }
    func sample() throws -> NSColor {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.08))
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      return try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 20, y: bitmap.pixelsHigh / 10)?.usingColorSpace(.sRGB))
    }
    let loading = try sample()
    XCTAssertGreaterThan(loading.blueComponent, loading.redComponent + 0.4)
    state.interrupt()
    let failure = try sample()
    XCTAssertGreaterThan(failure.redComponent, failure.blueComponent + 0.4)
  }

  @MainActor func testImageLoadingFollowsOverrideWithoutChangingOtherSunkSurfaces() throws {
    _ = NSApplication.shared
    for scheme in [ColorScheme.light, .dark] {
      for usesOverride in [false, true] {
        var override = OpenUITheme()
        override.sunk = .red
        if usesOverride { override.imagePlaceholderBackground = .blue }
        let theme = override.resolved()
        let view = HStack(spacing: 0) {
          NativeRemoteImage(src: nil, layout: .thumbnail(CGSize(width: 100, height: 100)), role: .content)
            .environment(\.openUIMediaSourceReady, false)
            .environment(\.openUIStreamActive, true)
            .frame(width: 100, height: 100)
          NativeLoadingSurface(active: false).frame(width: 100, height: 100)
        }
        .environment(\.openUITheme, theme)
        .environment(\.colorScheme, scheme)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 20, y: bitmap.pixelsHigh / 10)?.usingColorSpace(.sRGB))
        let other = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide * 11 / 20, y: bitmap.pixelsHigh / 10)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(other.redComponent, other.greenComponent + 0.4, "Other surfaces use themed sunk in \(scheme)")
        if usesOverride {
          XCTAssertGreaterThan(image.blueComponent, image.redComponent + 0.4, "Image override should be independent of sunk")
        } else {
          XCTAssertLessThan(abs(image.redComponent - image.greenComponent), 0.08, "Default image background should be neutral in \(scheme)")
          if scheme == .dark { XCTAssertLessThan(image.redComponent, 0.3) }
          else { XCTAssertGreaterThan(image.redComponent, 0.85) }
        }
      }
    }
  }
}
#endif
