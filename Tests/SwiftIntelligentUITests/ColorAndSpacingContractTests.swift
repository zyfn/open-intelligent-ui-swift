import XCTest
import SwiftUI
import CoreGraphics
import SwiftLang
@testable import SwiftIntelligentUI

/// Color/string and numeric contracts from @openuidev/intelligent-ui-library
/// at c531b0dfe83dc828241f71dbe77e689ebdbf05f7 (shared/props.ts and lib/schemas.ts).
final class ColorAndSpacingContractTests: XCTestCase {
    func testHexRGBAndHSLResolveTheSameAbsoluteColor() throws {
        let red = try XCTUnwrap(CSSColor.parse("#ff0000"))
        for source in ["#f00", "#FF0000", "red", " RED ", "rgb(255, 0, 0)",
                       "rgba(100%, 0%, 0%, 1)", "rgb(255 0 0 / 100%)",
                       "rgb(100% 0 0)", "hsl(0, 100%, 50%)", "hsl(1turn 100% 50%)",
                       "hsla(400grad 100% 50% / 1)", "hsl(0rad 100% 50%)"] {
            XCTAssertEqual(CSSColor.parse(source), red, source)
        }
        let blue = try XCTUnwrap(CSSColor.parse("hsl(-120deg 100% 50%)"))
        XCTAssertEqual(blue.red, 0, accuracy: 0.000_001)
        XCTAssertEqual(blue.green, 0, accuracy: 0.000_001)
        XCTAssertEqual(blue.blue, 1, accuracy: 0.000_001)
        XCTAssertEqual(CSSColor.parse("hsl(120 100% 50%)"), CSSColor.parse("lime"))
        XCTAssertEqual(CSSColor.parse("green"), CSSColor.parse("#008000"),
                       "CSS named green is not the native semantic .green color")
    }

    func testAlphaAndOutOfRangeChannelsFollowCSSClamping() throws {
        let short = try XCTUnwrap(CSSColor.parse("#0f08"))
        XCTAssertEqual(short.red, 0)
        XCTAssertEqual(short.green, 1)
        XCTAssertEqual(short.blue, 0)
        XCTAssertEqual(short.alpha, 8.0 / 15)
        XCTAssertEqual(CSSColor.parse("#ff000080")?.alpha, 128.0 / 255)
        XCTAssertEqual(CSSColor.parse("rgba(255, 0, 0, .5)")?.alpha, 0.5)
        XCTAssertEqual(CSSColor.parse("hsl(0 100% 50% / 25%)")?.alpha, 0.25)
        XCTAssertEqual(CSSColor.parse("rgb(300 -20 0 / 200%)"), CSSColor.parse("red"))
        XCTAssertEqual(CSSColor.parse("rgba(255, 0, 0, -1)")?.alpha, 0)
        XCTAssertEqual(CSSColor.parse("transparent")?.alpha, 0)
    }

    func testNamedColorsIncludeAllStandardNamesAndAliases() {
        XCTAssertEqual(CSSColor.namedColors.count, 148)
        XCTAssertEqual(CSSColor.parse("rebeccapurple"), CSSColor.parse("#663399"))
        XCTAssertEqual(CSSColor.parse("LightGoldenRodYellow"), CSSColor.parse("#fafad2"))
        XCTAssertEqual(CSSColor.parse("darkslategrey"), CSSColor.parse("darkslategray"))
        XCTAssertEqual(CSSColor.parse("cyan"), CSSColor.parse("aqua"))
        XCTAssertEqual(CSSColor.parse("magenta"), CSSColor.parse("fuchsia"))
    }

    func testColorsCannotContainResourcesExpressionsOrMarkup() {
        for source in ["url(https://example.com/paint)", "URL (https://example.com/paint)",
                       "var(--paint)", "env(theme-color)", "attr(data-color)",
                       "image-set(url(a) 1x)", "paint(custom)", "expression(alert(1))",
                       "@import 'https://example.com/style'", "red; background:url(a)",
                       "<style>red</style>", "red{}", #"\72 ed"#,
                       "rgb(calc(10 + 2) 0 0)", "rgb(1e999 0 0)",
                       "rgb(NaN 0 0)", "rgb(infinity 0 0)",
                       "rgb(20%, 2, 0)", "rgb(1, 2, 3 / .5)",
                       "rgb(1 2)", "rgb(1 2 3 /)", "#12", "#gggggg", "unknown"] {
            XCTAssertNil(CSSColor.parse(source), source)
            XCTAssertNil(SVGMarkup.paint(source), source)
        }
    }

    func testUnsupportedBrowserColorFeaturesAreNotGuessed() {
        for source in ["lab(50% 0 0)", "lch(50% 30 20)", "oklab(.5 0 0)",
                       "oklch(.5 .2 30)", "color(display-p3 1 0 0)",
                       "color-mix(in srgb, red, blue)", "rgb(from red r g b)",
                       "inherit", "revert", "currentColor"] {
            XCTAssertNil(CSSColor.parse(source), source)
        }
        // SVG's own inherited paint keywords are handled by the SVG renderer.
        XCTAssertEqual(SVGMarkup.paint("currentColor"), "currentColor")
        XCTAssertEqual(SVGMarkup.paint("none"), "none")
        XCTAssertEqual(SVGMarkup.paint("rgb(255 0 0 / 50%)"), "rgb(255 0 0 / 50%)")
        XCTAssertEqual(SVGMarkup.paint("hsl(120deg 100% 50%)"), "hsl(120deg 100% 50%)")
    }

    func testForegroundAndBackgroundTokensKeepTheirSeparateRoles() throws {
        var theme = OpenIntelligentUITheme()
        theme.primaryText = .black
        theme.secondaryText = .gray
        theme.faintText = .gray.opacity(0.5)
        theme.canvas = .white
        theme.surface = .yellow
        theme.surfaceStrong = .orange
        theme.fieldBorder = .brown
        theme.info = .blue
        XCTAssertEqual(theme.textColor("canvas"), theme.canvas)
        XCTAssertEqual(theme.textColor("faint"), theme.faintText)
        XCTAssertEqual(theme.backgroundColor("canvas"), theme.canvas)
        XCTAssertEqual(theme.backgroundColor("muted"), theme.secondaryText)
        XCTAssertEqual(theme.backgroundColor("faint"), theme.faintText)
        XCTAssertNotEqual(theme.backgroundColor("muted"), theme.surface)
        XCTAssertEqual(theme.backgroundColor("surface-strong"), theme.surfaceStrong)
        XCTAssertEqual(theme.backgroundColor("border"), theme.fieldBorder)
        XCTAssertEqual(theme.textColor("surface-strong"), theme.primaryText)
        XCTAssertEqual(theme.textColor("border"), theme.primaryText)
        XCTAssertEqual(theme.textColor("info"), theme.info)
        XCTAssertEqual(theme.backgroundColor("info"), theme.info.opacity(0.12))
        for index in 1...6 {
            XCTAssertEqual(theme.backgroundColor("chart\(index)"), theme.chartColors[index - 1])
            XCTAssertEqual(SVGMarkup.paint("chart\(index)", palette: ["chart\(index)": "#123456"]), "#123456")
        }
        XCTAssertEqual(SVGMarkup.paint("canvas", palette: ["canvas": "#ffffff"]), "#ffffff")
        let explicit = try XCTUnwrap(CSSColor.parse("rgba(10, 20, 30, .5)")).color
        XCTAssertEqual(theme.textColor("rgba(10, 20, 30, .5)"), explicit)
        XCTAssertEqual(theme.backgroundColor("rgba(10, 20, 30, .5)"), explicit)
        XCTAssertEqual(theme.backgroundColor("url(a)"), .clear)
        XCTAssertEqual(theme.textColor("url(a)"), theme.primaryText)
    }

    func testSpacingAndNumericRadiusHaveNoPrivateUpperLimit() {
        var theme = OpenIntelligentUITheme()
        XCTAssertEqual(theme.spacing(30), 120)
        XCTAssertEqual(theme.spacing(1024), 4096)
        XCTAssertEqual(theme.spacing(-2), 0)
        XCTAssertEqual(theme.spacing(nil, fallback: 3), 12)
        XCTAssertEqual(theme.spacing(.nan, fallback: 3), 12)
        XCTAssertEqual(theme.spacing(.infinity, fallback: 3), 12)
        XCTAssertTrue(theme.spacing(Double.greatestFiniteMagnitude, fallback: 3).isFinite)
        theme.spacingUnit = 8
        XCTAssertEqual(theme.spacing(30), 240)
        XCTAssertEqual(theme.radius(named: nil, points: 20_001), 20_001)
        XCTAssertEqual(theme.radius(named: nil, points: -2), 0)
        XCTAssertEqual(theme.radius(named: "full"), 999)
        XCTAssertEqual(theme.radius(named: nil, points: .infinity, fallback: 12), 12)
        XCTAssertEqual(CarouselMetrics.width(preferred: 1_000, available: 2_000, accessibility: false), 640)
        XCTAssertEqual(CarouselMetrics.width(preferred: 1, available: 2_000, accessibility: false), 80)
    }

    func testRawBackgroundContrastFollowsUpstreamScopeAndPreservesExplicitColors() throws {
        let theme = OpenIntelligentUITheme()
        let white = try XCTUnwrap(CSSColor.parse("#fff")).color
        let dark = try XCTUnwrap(CSSColor.parse("#0d0d0d")).color
        let onBlack = theme.onBackground("#000")
        XCTAssertEqual(onBlack.primaryText, white)
        XCTAssertEqual(onBlack.secondaryText, white.opacity(0.72))
        XCTAssertEqual(onBlack.faintText, white.opacity(0.55))
        XCTAssertEqual(onBlack.actionAccent, white)
        XCTAssertEqual(onBlack.actionForeground, dark)
        XCTAssertEqual(theme.onBackground("#ffffff").primaryText, dark)
        XCTAssertEqual(theme.onBackground("rgb(255, 255, 255)").primaryText, dark)
        XCTAssertEqual(theme.onBackground("rgba(0, 0, 0, .1)").primaryText, white,
                       "Upstream contrast ignores alpha rather than compositing against a guessed canvas")
        XCTAssertEqual(theme.onBackground("#a0a0a0").primaryText, white)
        XCTAssertEqual(theme.onBackground("#a3a3a3").primaryText, dark)
        for background in ["ink", "muted", "faint", "canvas", "surface", "surface-strong", "border",
                           "info", "pink", "chart1", "white", "#000f", "#000000ff",
                           "hsl(0 0% 0%)", "rgb(.5 0 0)", "url(a)"] {
            XCTAssertEqual(theme.onBackground(background), theme, background)
        }
        let red = try XCTUnwrap(CSSColor.parse("#ff0000")).color
        XCTAssertEqual(onBlack.textColor(nil), white)
        XCTAssertEqual(onBlack.textColor("ink"), white)
        XCTAssertEqual(onBlack.textColor("#ff0000"), red)
        XCTAssertEqual(onBlack.textColor("info"), theme.info)
        XCTAssertEqual(theme.primaryText, OpenIntelligentUITheme().primaryText,
                       "Deriving a subtree's text colors must not mutate its parent theme")
    }

    @MainActor func testRawBackgroundChangesDefaultTextWhileExplicitChildPaintRemainsVisible() throws {
        let library = try OpenIntelligentUIComponents()
        let children = ##"[ListItem("Default"), Text("Explicit", "md", "#ff0000")]"##
        let containers = [
            "Box(\(children), \"col\", 2, 4, \"#000000\")",
            "Pressable(\(children), @ToAssistant(\"Continue\"), false, 4, \"#000000\")"
        ]
        for container in containers {
            let state = library.makeState()
            state.setSource("root = Col([\(container)])")
            XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
            var theme = OpenIntelligentUITheme()
            theme.primaryText = .black
            theme.canvas = .black
            let renderer = ImageRenderer(content: OpenIntelligentUIContentView(state: state, library: library)
                .openIntelligentUITheme(theme).frame(width: 320).background(.black))
            let image = try XCTUnwrap(renderer.cgImage)
            let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            var whitePixels = 0, redPixels = 0
            for index in 0..<(image.width * image.height) where pixels[index * 4 + 3] > 200 {
                let red = pixels[index * 4], green = pixels[index * 4 + 1], blue = pixels[index * 4 + 2]
                if red > 200 && green > 200 && blue > 200 { whitePixels += 1 }
                if red > 200 && green < 50 && blue < 50 { redPixels += 1 }
            }
            XCTAssertGreaterThan(whitePixels, 10, "Default text needs the subtree's white ink: \(container)")
            XCTAssertGreaterThan(redPixels, 10, "Explicit red text must keep its paint: \(container)")
        }
    }

    func testRawBackgroundPreservesTextAndPlaceholderOnNativeCanvasFields() throws {
        var theme = OpenIntelligentUITheme()
        theme.canvas = .white
        theme.primaryText = .black
        theme.secondaryText = .gray
        theme.actionAccent = .blue
        let contentTheme = theme.onBackground("#000000")
        let white = try XCTUnwrap(CSSColor.parse("#fff")).color
        XCTAssertEqual(contentTheme.primaryText, white, "Labels outside the field sit on the dark Box")
        XCTAssertEqual(contentTheme.canvas, .white, "The native field still owns its opaque canvas")
        XCTAssertEqual(contentTheme.fieldText, .black, "Input/editor values must not become white on white")
        XCTAssertEqual(contentTheme.fieldSecondaryText, .gray, "TextArea and selection placeholders keep the canvas's secondary ink")
        XCTAssertEqual(contentTheme.fieldAccent, .blue, "Focus borders and the caret belong to that same native surface")
        let nested = contentTheme.onBackground("#ffffff").onBackground("#000000")
        XCTAssertEqual(nested.fieldText, theme.fieldText, "Nested raw surfaces must not replace the canvas's saved ink")
        XCTAssertEqual(nested.fieldSecondaryText, theme.fieldSecondaryText)
        XCTAssertEqual(nested.fieldAccent, theme.fieldAccent)
    }

    func testRawBackgroundKeepsOpaqueButtonVariantsReadableAndExplicitStatusColors() throws {
        var theme = OpenIntelligentUITheme()
        theme.actionAccent = .black
        theme.onAccent = .yellow
        let onBlack = theme.onBackground("#000000")
        let white = try XCTUnwrap(CSSColor.parse("#fff")).color
        for variant in ["outline", "soft"] {
            XCTAssertEqual(onBlack.buttonAccent(nil, variant: variant), .black,
                           "Native opaque surfaces keep the base accent, not the surrounding white ink")
            XCTAssertEqual(onBlack.buttonAccent("primary", variant: variant), .black)
        }
        for variant in ["solid", "ghost"] {
            XCTAssertEqual(onBlack.buttonAccent(nil, variant: variant), white)
        }
        for variant in ["solid", "outline", "soft", "ghost"] {
            XCTAssertEqual(onBlack.buttonAccent("danger", variant: variant), theme.danger)
            XCTAssertEqual(onBlack.buttonAccent("success", variant: variant), theme.success)
        }
        XCTAssertEqual(onBlack.onAccent, .yellow,
                       "An explicitly colored solid button keeps its existing onAccent foreground")
    }

    func testGeneratedSchemasAcceptColorsAndUnboundedSpacing() throws {
        let library = try OpenIntelligentUIComponents()
        let components = library.components.library.components
        for (name, field) in [("Text", "color"), ("Title", "color"), ("Caption", "color"),
                              ("Icon", "color"), ("Box", "background"), ("Pressable", "background")] {
            let component = try XCTUnwrap(components.first { $0.name == name })
            let parameter = try XCTUnwrap(component.params.first { $0.name == field })
            XCTAssertEqual(parameter.schema, Parameter.stringSchema, "\(name).\(field)")
        }
        for (name, field) in [("Col", "gap"), ("Row", "gap"), ("Box", "gap"), ("Box", "padding"),
                              ("Grid", "gap"), ("Card", "gap"), ("Card", "padding"),
                              ("Carousel", "gap"), ("Carousel", "itemWidth"), ("Pressable", "padding")] {
            let component = try XCTUnwrap(components.first { $0.name == name })
            let parameter = try XCTUnwrap(component.params.first { $0.name == field })
            XCTAssertEqual(parameter.schema, Parameter.numberSchema, "\(name).\(field)")
        }
    }

    @MainActor func testCustomColorsLargeSpacingAndNegativeRadiusParseInTheGenerationContract() throws {
        let library = try OpenIntelligentUIComponents()
        let source = #"""
        root = Col([Box([Title("Color", "md", "#ff000080"), Text("Body", "md", "rgb(0 20 30 / .5)"), Caption("Note", "rebeccapurple"), Icon("camera", "md", "hsl(120deg 100% 50%)")], "col", 32, 36, "surface-strong", -1), Card([Text("Large space")], "outline", 40, 48), Carousel([Text("Item")], 1000, 30), Pressable([Text("Action")], @ToAssistant("Continue"), false, 30, "rgba(0, 0, 255, .1)", 20001)], -2)
        """#
        let state = library.makeState()
        state.setSource(source)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        XCTAssertNotNil(state.root)
        XCTAssertEqual(library.validationIssues(in: state, source: source, profile: .generation), [])
    }
}
