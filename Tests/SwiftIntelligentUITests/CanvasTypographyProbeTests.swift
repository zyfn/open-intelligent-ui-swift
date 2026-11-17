#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import SwiftIntelligentUI

/// An isolated experiment, not a production typography implementation.
final class CanvasTypographyProbeTests: XCTestCase {
    @MainActor func testCanvasResolvesSemanticAndFixedBaselines() {
        let theme = OpenIntelligentUITheme()
        var recipes: [CanvasFontRecipe] = []
        for (level, role, nativeAdvance, fixedAdvance) in [
            (1, "xl", CGFloat(22), CGFloat(20)),
            (2, "lg", CGFloat(20), CGFloat(19)),
            (3, "md", CGFloat(16), CGFloat(16)),
        ] {
            let native = InlineFonts.styled(
                InlineFonts.semantic(style: MarkdownTypography.nativeHeadingStyle(level: level), typeSize: .large),
                weight: theme.headingWeight, tabular: false, italic: false)
            let adapter = MarkdownFontStyle(native)
            recipes.append(.init(role: role, name: "semantic",
                                 font: TitleTypography.font(size: role, theme: theme), expectedAdvance: nativeAdvance))
            recipes.append(.init(role: role, name: "native", font: Font(native), expectedAdvance: nativeAdvance))
            recipes.append(.init(role: role, name: "fixed",
                                 font: Font.system(size: adapter.size.rounded()).weight(adapter.weight),
                                 expectedAdvance: fixedAdvance))
        }

        for scale in [CGFloat(1), CGFloat(2)] {
            for recipe in recipes {
                inspect(CanvasBaselineProbe.measure(font: recipe.font, scale: scale),
                        recipe: recipe, scale: scale, phase: "direct")
            }
        }

        // A fresh renderer and result box are created from the outer View.body.
        // No cache, SDK state, window, task, run-loop pumping, or image sampling.
        let cold = CanvasColdResultBox()
        let outer = ImageRenderer(content: CanvasColdCallView(
            recipes: recipes.filter { $0.role == "lg" }, scale: 2, results: cold))
        outer.scale = 2
        let outerImage = outer.cgImage
        print("Canvas typography outer: image=\(outerImage != nil) bodyEvaluations=\(cold.bodyEvaluations) nestedMeasurements=\(cold.measurements.count)")
        XCTAssertNotNil(outerImage, "The outer renderer must finish synchronously")
        XCTAssertGreaterThan(cold.bodyEvaluations, 0, "The outer body must actually run")
        XCTAssertGreaterThan(cold.measurements.count, 0, "Nested Canvas calibration must run in body")
        for (recipe, measurement) in cold.measurements {
            inspect(measurement, recipe: recipe, scale: 2, phase: "outer-body-cold")
        }
    }

    private func inspect(_ measurement: CanvasMeasurement, recipe: CanvasFontRecipe,
                         scale: CGFloat, phase: String) {
        let context = "phase=\(phase) role=\(recipe.role) recipe=\(recipe.name) scale=\(scale)"
        print("Canvas typography: \(context) image=\(measurement.imageAvailable) pixels=\(measurement.pixelWidth)x\(measurement.pixelHeight) callbacks=\(measurement.samples.count) expectedAdvance=\(recipe.expectedAdvance)")
        XCTAssertTrue(measurement.imageAvailable, context)
        XCTAssertEqual(measurement.pixelWidth, Int(scale), context)
        XCTAssertEqual(measurement.pixelHeight, Int(scale), context)
        XCTAssertFalse(measurement.samples.isEmpty, "Canvas must supply a result before cgImage returns: \(context)")
        for sample in measurement.samples {
            let advance = sample.lastBaseline - sample.firstBaseline
            print("Canvas typography baseline: \(context) first=\(sample.firstBaseline) last=\(sample.lastBaseline) advance=\(advance) measured=\(sample.size) mainThread=\(sample.mainThread)")
            XCTAssertTrue(sample.firstBaseline.isFinite && sample.lastBaseline.isFinite, context)
            XCTAssertTrue(sample.size.width.isFinite && sample.size.height.isFinite, context)
            XCTAssertGreaterThan(advance, 0, "Both nonempty lines must participate: \(context)")
            // These are the independently observed SwiftUI Text advances. A
            // mismatch establishes that Canvas is not an equivalent oracle.
            XCTAssertEqual(advance, recipe.expectedAdvance, accuracy: 0.01, context)
        }
    }
}

private struct CanvasFontRecipe {
    let role: String
    let name: String
    let font: Font
    let expectedAdvance: CGFloat
}

private struct CanvasBaselineSample {
    let firstBaseline: CGFloat
    let lastBaseline: CGFloat
    let size: CGSize
    let mainThread: Bool
}

private struct CanvasMeasurement {
    let imageAvailable: Bool
    let pixelWidth: Int
    let pixelHeight: Int
    let samples: [CanvasBaselineSample]
}

/// No observable state is written by the renderer closure. The lock also lets
/// the experiment report an unexpected callback thread without a data race.
private final class CanvasBaselineResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [CanvasBaselineSample] = []

    func record(_ sample: CanvasBaselineSample) {
        lock.lock()
        defer { lock.unlock() }
        samples.append(sample)
    }

    func snapshot() -> [CanvasBaselineSample] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }
}

@MainActor private enum CanvasBaselineProbe {
    static func measure(font: Font, scale: CGFloat) -> CanvasMeasurement {
        let result = CanvasBaselineResultBox()
        let content = Canvas(rendersAsynchronously: false) { context, _ in
            let text = context.resolve(Text(verbatim: "Heading\nHeading").font(font))
            let area = CGSize(width: 1_000, height: 1_000)
            result.record(.init(firstBaseline: text.firstBaseline(in: area),
                                lastBaseline: text.lastBaseline(in: area),
                                size: text.measure(in: area), mainThread: Thread.isMainThread))
            // Deliberately do not draw. Only public text metrics are queried.
        }
        .frame(width: 1, height: 1)
        .environment(\.displayScale, scale)
        .environment(\.dynamicTypeSize, .large)
        .environment(\.lineSpacing, 0)
        .environment(\.locale, Locale(identifier: "en_US_POSIX"))
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        let image = renderer.cgImage
        return .init(imageAvailable: image != nil, pixelWidth: image?.width ?? 0,
                     pixelHeight: image?.height ?? 0, samples: result.snapshot())
    }
}

@MainActor private final class CanvasColdResultBox {
    var bodyEvaluations = 0
    var measurements: [(CanvasFontRecipe, CanvasMeasurement)] = []
}

@MainActor private struct CanvasColdCallView: View {
    let recipes: [CanvasFontRecipe]
    let scale: CGFloat
    let results: CanvasColdResultBox

    var body: some View {
        let _ = measureInBody()
        Color.clear.frame(width: 1, height: 1)
    }

    private func measureInBody() {
        results.bodyEvaluations += 1
        for recipe in recipes {
            results.measurements.append((recipe, CanvasBaselineProbe.measure(font: recipe.font, scale: scale)))
        }
    }
}
#endif
