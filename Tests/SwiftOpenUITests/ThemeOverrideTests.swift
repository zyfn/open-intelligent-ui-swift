import SwiftLang
#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import SwiftOpenUI

final class ThemeOverrideTests: XCTestCase {
  @MainActor func testNestedThemeReachesCustomCoreComponentsWithoutErasingHostContext() throws {
    _ = NSApplication.shared
    var nested = OpenUIThemeValues(); nested.spaceM = 47
    let scope = OpenUIComponent(name: "ProbeThemeScope", description: "Local theme scope",
      params: [OpenUIParameter.slot("children", required: true)]) { context in
      context.slot().environment(\.openUITheme, nested)
    }
    let metric = OpenUIComponent(name: "ProbeMetric", description: "Read the closest theme", params: []) { context in
      Color.clear.frame(height: context.values[HostContextProbe.self] == "retained" ? context.theme.spaceM : 1)
    }
    let library = try OpenUIComponentLibrary(components: [scope, metric], root: "ProbeThemeScope")
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource("root=ProbeThemeScope([ProbeMetric()])")
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    var outer = OpenUIThemeValues(); outer.spaceM = 11
    var values = OpenUIContextValues(); values[HostContextProbe.self] = "retained"
    let hosting = NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
      .openUITheme(outer).openUIContextValues(values).frame(width: 200))
    XCTAssertEqual(hosting.fittingSize.height, 47, accuracy: 0.5,
      "A nested standard theme must reach any registered component while preserving unrelated host context")
  }

  @MainActor func testListTitlesAndCompactDescriptionsUseTheirIndependentThemeFonts() throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    func height(_ source: String, _ theme: OpenUIThemeValues) -> CGFloat {
      let state = OpenUIState(schema: library.library.toSchema()); state.setSource(source)
      XCTAssertTrue(state.errors.isEmpty)
      return NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
        .openUITheme(theme).frame(width: 320)).fittingSize.height
    }
    let list = "root=ListBlock([ListItem(\"A clear place name\",\"A supporting explanation\")],\"number\")"
    let heading = "root=InlineHeader(\"A section\",\"A supporting explanation\")"
    let base = OpenUIThemeValues()
    var titles = base; titles.textBodyDefaultHeavy = OpenUIFont(size: 32, weight: .light)
    XCTAssertGreaterThan(height(list, titles), height(list, base) + 8)
    XCTAssertEqual(height(heading, titles), height(heading, base), accuracy: 1)
    var descriptions = base; descriptions.textBodySm = OpenUIFont(size: 28)
    XCTAssertGreaterThan(height(heading, descriptions), height(heading, base) + 8)
  }

  func testResolvingUnchangedOverridesPreservesColorIdentity() {
    let first = OpenUITheme().resolved()
    let second = OpenUITheme().resolved()
    XCTAssertEqual(first.textNeutralPrimary, second.textNeutralPrimary)
    XCTAssertEqual(first.background, second.background)
    XCTAssertEqual(first.sunk, second.sunk)
    XCTAssertEqual(first.interactiveAccentDisabled, second.interactiveAccentDisabled)
  }

  func testPublishedSpacingAndRadiusDefaultsStayUnchanged() {
    let theme = OpenUIThemeValues()
    let keys = ["none", "3xs", "2xs", "xs", "s", "sm", "m", "ml", "l", "xl", "2xl", "3xl"]
    XCTAssertEqual(keys.map { theme.spacing($0) }, [0, 2, 4, 6, 8, 10, 12, 16, 18, 24, 36, 48])
    XCTAssertEqual(theme.spacing(nil), 12)
    XCTAssertEqual(theme.spacing("unknown"), 12)
    XCTAssertEqual([theme.radiusL, theme.radius3xl, theme.radiusM, theme.radius5xl], [10, 16, 8, 24])
    XCTAssertEqual([theme.cardRadius(for: "Context"), theme.cardRadius(for: "Overview"), theme.cardRadius(for: "Composite")], [12, 14, 16])
  }

  func testMediumShadowResolvesThePinnedReferenceLayersForEachAppearance() {
    // openui 7b7a51985814d37201e16ece44d28a996bdfa528, openui-defaults.scss.
    // These are CSS blur radii; the renderer converts them to Gaussian sigma.
    let shadow = OpenUIThemeValues().shadowM
    XCTAssertEqual(shadow.resolvedLayers(for: .light), [
      OpenUIShadow.Layer(opacity: 0.025, blurRadius: 6, y: 4, spread: -2),
      OpenUIShadow.Layer(opacity: 0.05, blurRadius: 2, y: 2, spread: -2)
    ])
    XCTAssertEqual(shadow.resolvedLayers(for: .dark), [
      OpenUIShadow.Layer(opacity: 0.08, blurRadius: 6, y: 4, spread: -2),
      OpenUIShadow.Layer(opacity: 0.12, blurRadius: 2, y: 2, spread: -2)
    ])
  }

  func testMediumShadowHostOverridesPreserveSingleLayerRadiusAndExplicitNone() {
    let makeShadow: (Double, CGFloat, CGFloat, CGFloat) -> OpenUIShadow = OpenUIShadow.init(opacity:radius:x:y:)
    let native = makeShadow(0.31, 5, -3, 7)
    for scheme in [ColorScheme.light, .dark] {
      XCTAssertEqual(native.resolvedLayers(for: scheme), [
        OpenUIShadow.Layer(opacity: 0.31, blurRadius: 10, x: -3, y: 7)
      ], "The original four-argument initializer remains usable as a function value")
    }
    var overrides = OpenUITheme()
    overrides.shadowM = OpenUIShadow(opacity: 0.31, radius: 5, x: -3, y: 7, spread: 1)
    let expected = [OpenUIShadow.Layer(opacity: 0.31, blurRadius: 10, x: -3, y: 7, spread: 1)]
    for scheme in [ColorScheme.light, .dark] {
      XCTAssertEqual(overrides.resolved().shadowM.resolvedLayers(for: scheme), expected,
        "The existing native-radius initializer remains a complete host override in either appearance")
    }
    overrides.shadowM = OpenUIShadow()
    for scheme in [ColorScheme.light, .dark] {
      XCTAssertTrue(overrides.resolved().shadowM.resolvedLayers(for: scheme).allSatisfy { $0.opacity == 0 },
        "An explicit no-shadow value must never restore the default layered recipe")
    }
    var adaptive = OpenUIShadow(layers: expected)
    XCTAssertEqual(adaptive.resolvedLayers(for: .dark), expected,
      "An absent dark recipe inherits the host's light layers")
    adaptive.darkLayers = []
    XCTAssertEqual(adaptive.resolvedLayers(for: .dark), [],
      "An explicit empty dark recipe disables shadows instead of falling back to the light recipe")
    XCTAssertEqual(adaptive.resolvedLayers(for: .light), expected)
  }

  func testEditingTheExistingOpacityPropertyCanDisableTheWholeAdaptiveShadow() {
    var shadow = OpenUIThemeValues().shadowM
    shadow.opacity = 0
    XCTAssertNil(shadow.darkLayers)
    for scheme in [ColorScheme.light, .dark] {
      let layers = shadow.resolvedLayers(for: scheme)
      XCTAssertEqual(layers.count, 1)
      XCTAssertEqual(layers.first?.opacity, 0,
        "Changing the existing scalar API replaces the complete recipe, including its dark layers")
    }
  }

  func testOverridesResolveWithoutHiddenPaddingOrRadiusAliases() {
    var overrides = OpenUITheme()
    overrides.spaceM = 20; overrides.radius3xl = 22; overrides.radiusXl = 5
    let theme = overrides.resolved()
    XCTAssertEqual(theme.spacing("m"), 20)
    XCTAssertEqual(theme.cardRadius(for: "Composite"), 22)
    XCTAssertEqual(theme.cardRadius(for: "Context"), 5)
    XCTAssertEqual(theme.cardRadius(for: "Overview"), 14)
    XCTAssertEqual(theme.spaceSM, 10, "Compact cards have their own official spacing token")
    XCTAssertEqual(OpenUITheme().resolved().spaceM, 12)
  }

  @MainActor func testStackAndCardReadTheSameOverriddenSpacing() throws {
    _ = NSApplication.shared
    let standard = try OpenUIComponents.library()
    let text = try XCTUnwrap(standard.library.components.first { $0.name == "TextContent" })
    let library = try standard.extending(overriding: [OpenUIComponent(text) { _ in
      Color.primary.frame(height: 10)
    }])
    func height(_ source: String, _ theme: OpenUIThemeValues) throws -> CGFloat {
      let state = OpenUIState(schema: library.library.toSchema()); state.setSource(source)
      XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
      return NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
        .openUITheme(theme).frame(width: 300)).fittingSize.height
    }
    let base = OpenUIThemeValues(); var custom = base
    // Standard sunk Card takes its padding from space-l; the child gap uses m.
    custom.spaceM = 22; custom.spaceL = 28
    let children = "[TextContent(\"A\"),TextContent(\"B\")]"
    XCTAssertEqual(try height("root=Stack(\(children))", custom) - height("root=Stack(\(children))", base), 10, accuracy: 0.5)
    XCTAssertEqual(try height("root=Card(\(children),\"sunk\")", custom) - height("root=Card(\(children),\"sunk\")", base), 30, accuracy: 0.5)
  }

  @MainActor func testTagPaddingUsesTheOverriddenToken() throws {
    _ = NSApplication.shared
    func height(_ theme: OpenUIThemeValues) -> CGFloat {
      NSHostingView(rootView: NativeTagPill(text: "Tag", size: "md", variant: nil, theme: theme) { EmptyView() }
        .openUITheme(theme).fixedSize()).fittingSize.height
    }
    let base = OpenUIThemeValues(); var custom = base; custom.space2xs = base.space2xs + 4
    XCTAssertEqual(height(custom) - height(base), 8, accuracy: 0.5)
  }

  func testTextRolesAreCompleteIndependentOverrides() {
    var overrides = OpenUITheme()
    overrides.textBodyDefault = OpenUIFont(size: 19)
    XCTAssertEqual(overrides.resolved().textBodyDefaultHeavy.size, 16)
    overrides.textBodyDefaultHeavy = OpenUIFont(size: 22, weight: .bold, lineSpacing: 0.3)
    overrides.textBodyDefault = OpenUIFont(size: 17)
    let theme = overrides.resolved()
    XCTAssertEqual(theme.textBodyDefault.size, 17)
    XCTAssertEqual(theme.textBodyDefaultHeavy.size, 22)
    XCTAssertEqual(theme.textBodyDefaultHeavy.weight, .bold)
    XCTAssertEqual(theme.textBodyDefaultHeavy.lineSpacing, 0.3)
  }

  @MainActor func testImageTextUsesTheCompleteObjectTitleFontForBothWeights() throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    func height(bold: Bool, theme: OpenUIThemeValues) -> CGFloat {
      let state = OpenUIState(schema: library.library.toSchema())
      state.setSource("root=ImageText(\"\",\"\",\"Product name\",\"Description\",\(bold),\"horizontal\",20)")
      return NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
        .openUITheme(theme).frame(width: 320)).fittingSize.height
    }
    let base = OpenUIThemeValues()
    var custom = base
    custom.textHeadingXs = OpenUIFont(size: 34, weight: .light, lineSpacing: 0.4)
    XCTAssertGreaterThan(height(bold: true, theme: custom), height(bold: true, theme: base) + 10)
    XCTAssertGreaterThan(height(bold: false, theme: custom), height(bold: false, theme: base) + 10)
  }

  @MainActor func testBannerTitleUsesObjectTitleWithoutChangingSubtitleRole() throws {
    _ = NSApplication.shared
    let library = try OpenUIComponents.library()
    let state = OpenUIState(schema: library.library.toSchema())
    state.setSource("root=ImageTextLarge(\"\",\"\",\"杭州兰郡酒店（西湖店）\",\"青年路31号｜平台标注舒适型\")")
    XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
    func height(_ theme: OpenUIThemeValues) -> CGFloat {
      NSHostingView(rootView: OpenUIContentView(state: state, registry: library.registry)
        .openUITheme(theme).frame(width: 360)).fittingSize.height
    }
    let base = OpenUIThemeValues(); var custom = base
    custom.textHeadingXs = OpenUIFont(size: 30, weight: .bold)
    XCTAssertGreaterThan(height(custom), height(base) + 10)
    XCTAssertEqual(custom.textBodySm, base.textBodySm)
  }

  @MainActor func testPerRoleLineSpacingReachesRenderedMarkdown() {
    _ = NSApplication.shared
    func height(_ font: OpenUIFont) -> CGFloat {
      NSHostingView(rootView: NativeMarkdownText(text: "First line\nSecond line\nThird line", mode: .inline,
        style: .init(font: font)).frame(width: 300)).fittingSize.height
    }
    let base = OpenUIFont(size: 16)
    var custom = base; custom.lineSpacing = 0.8
    XCTAssertGreaterThan(height(custom), height(base) + 8)
  }

  @MainActor func testLineHeightAndTrackingReachNativeAndMarkdownText() {
    _ = NSApplication.shared
    let base = OpenUIFont(size: 16)
    let taller = OpenUIFont(size: 16, lineHeight: 2.5)
    let wider = OpenUIFont(size: 16, letterSpacing: 0.15)
    func native(_ font: OpenUIFont) -> NSSize {
      NSHostingView(rootView: Text("One line\nTwo lines\nThree lines").openUIFont(font).fixedSize()).fittingSize
    }
    func markdown(_ font: OpenUIFont) -> NSSize {
      NSHostingView(rootView: NativeMarkdownText(text: "One line\nTwo lines\nThree lines", mode: .inline,
        style: .init(font: font)).frame(width: 300)).fittingSize
    }
    XCTAssertGreaterThan(native(taller).height, native(base).height + 10)
    XCTAssertGreaterThan(markdown(taller).height, markdown(base).height + 10)
    XCTAssertGreaterThan(native(wider).width, native(base).width + 5)
    XCTAssertEqual(OpenUIFont(size: 16, lineHeight: 0.1).additionalLineSpacing(), 0,
      "A requested line height cannot cut into native font metrics")
  }

  @MainActor func testInvertedAndLinkColorsHaveIndependentThemeRoles() throws {
    _ = NSApplication.shared
    func rgba(_ color: Color, _ appearance: NSAppearance.Name) throws -> [CGFloat] {
      var result: [CGFloat]?
      try XCTUnwrap(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
        if let c = NSColor(color).usingColorSpace(.sRGB) { result = [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent] }
      }
      return try XCTUnwrap(result)
    }
    for scheme in [NSAppearance.Name.aqua, .darkAqua] {
      let base = OpenUIThemeValues()
      let original = NativeBadgeColors(variant: "inverted", theme: base)
      XCTAssertEqual(try rgba(original.foreground, scheme), try rgba(base.background, scheme))
      XCTAssertEqual(try rgba(original.background, scheme), try rgba(base.invertedBackground, scheme))
      var changed = base; changed.background = .pink
      XCTAssertEqual(try rgba(NativeBadgeColors(variant: "inverted", theme: changed).foreground, scheme), try rgba(original.foreground, scheme))
      changed.textAccentPrimary = .yellow; changed.invertedBackground = .blue; changed.textNeutralLink = .green
      let colors = NativeBadgeColors(variant: "inverted", theme: changed)
      XCTAssertEqual(try rgba(colors.foreground, scheme), try rgba(.yellow, scheme))
      XCTAssertEqual(try rgba(colors.background, scheme), try rgba(.blue, scheme))
      XCTAssertEqual(try rgba(changed.textNeutralLink, scheme), try rgba(.green, scheme))
      XCTAssertEqual(try rgba(changed.textNeutralPrimary, scheme), try rgba(base.textNeutralPrimary, scheme))
    }
  }
}

private enum HostContextProbe: OpenUIContextKey {
  static let defaultValue = "missing"
}
#endif
