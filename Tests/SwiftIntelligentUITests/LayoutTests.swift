import XCTest
import SwiftUI
import SwiftLang
@testable import SwiftIntelligentUI
#if os(macOS)
import AppKit
#endif

final class LayoutTests: XCTestCase {
    func testWrappingKeepsMultipleItemsOnEachLine() {
        let geometry = RowGeometry(sizes: Array(repeating: CGSize(width: 40, height: 20), count: 5),
                                   width: 100, gap: 10, alignment: "start", justification: "start", wraps: true)
        XCTAssertEqual(geometry.frames.map(\.minX), [0, 50, 0, 50, 0])
        XCTAssertEqual(geometry.frames.map(\.minY), [0, 0, 30, 30, 60])
        XCTAssertEqual(geometry.size, CGSize(width: 100, height: 80))
    }

    func testRowAlignmentAndJustification() {
        let sizes = [CGSize(width: 20, height: 10), CGSize(width: 30, height: 30)]
        let between = RowGeometry(sizes: sizes, width: 100, gap: 10, alignment: "end", justification: "between", wraps: true)
        XCTAssertEqual(between.frames[0], CGRect(x: 0, y: 20, width: 20, height: 10))
        XCTAssertEqual(between.frames[1].maxX, 100)
        let center = RowGeometry(sizes: sizes, width: 100, gap: 10, alignment: "stretch", justification: "center", wraps: false)
        XCTAssertEqual(center.frames[0].minX, 20)
        XCTAssertEqual(center.frames.map(\.height), [30, 30])
    }

    func testSingleBetweenItemAndEmptyRow() {
        let geometry = RowGeometry(sizes: [CGSize(width: 40, height: 20)], width: 100, gap: 12, alignment: "start", justification: "between", wraps: true)
        XCTAssertEqual(geometry.frames[0].minX, 0)
        XCTAssertEqual(RowGeometry(sizes: [], width: 100, gap: 12, alignment: "start", justification: "start", wraps: true).size, .zero)
        let oversized = [CGSize(width: 80, height: 20), CGSize(width: 80, height: 20)]
        XCTAssertEqual(RowGeometry(sizes: oversized, width: 100, gap: 10, alignment: "start", justification: "center", wraps: false).frames[0].minX, -35)
        XCTAssertEqual(RowGeometry(sizes: oversized, width: 100, gap: 10, alignment: "start", justification: "end", wraps: false).frames[0].minX, -70)
    }

    func testAdaptiveGridHonorsMaximumColumnsAndNarrowWidth() {
        let grid = EqualGridLayout(columns: 3, minimumWidth: 120, gap: 12)
        XCTAssertEqual(grid.columnCount(width: 1000), 3)
        XCTAssertEqual(grid.columnCount(width: 260), 2)
        XCTAssertEqual(grid.columnCount(width: 120), 1)
        XCTAssertEqual(grid.columnCount(width: 20), 1)
        XCTAssertEqual(EqualGridLayout(columns: 2, minimumWidth: nil, gap: 12).columnCount(width: 1000), 2)
    }

    func testPinnedFlexShorthandAndNumericWidthNoShrinkRule() {
        // Independent contract: c531b0d Box.tsx uses `flex != null` before
        // `typeof width === "number"`; row.styles.ts sets child min-width: 0.
        XCTAssertEqual(FlexDistribution.lengths([FlexBasis(basis: 0, grow: 1), FlexBasis(basis: 0, grow: 1)], available: 312), [156, 156])
        XCTAssertEqual(FlexDistribution.lengths([FlexBasis(basis: 0, grow: 0), FlexBasis(basis: 0, grow: 1)], available: 312), [0, 312])
        XCTAssertEqual(FlexDistribution.lengths([FlexBasis(basis: 96), FlexBasis(basis: 96, shrink: 0)], available: 120), [24, 96])
        XCTAssertEqual(FlexDistribution.lengths([FlexBasis(basis: 16, minimum: 16, insets: 16), FlexBasis(basis: 0, grow: 1)], available: 312), [16, 296])
        XCTAssertEqual(FlexDistribution.lengths([FlexBasis(basis: 0, grow: 0.25)], available: 200), [50])
        XCTAssertEqual(FlexDistribution.lengths([FlexBasis(basis: 0, minimum: 200), FlexBasis(basis: 0, grow: 0.5)], available: 400), [200, 100])
    }

    func testColumnFlexPreservesAutomaticContentMinimums() {
        XCTAssertEqual(FlexDistribution.lengths([FlexBasis(basis: 0, minimum: 20, grow: 1),
            FlexBasis(basis: 0, minimum: 20, grow: 1)], available: 192), [96, 96])
        XCTAssertEqual(FlexDistribution.lengths([FlexBasis(basis: 0, minimum: 20),
            FlexBasis(basis: 0, minimum: 20, grow: 1)], available: 192), [20, 172])
        XCTAssertEqual(FlexDistribution.lengths([FlexBasis(basis: 0, grow: 2000),
            FlexBasis(basis: 0, grow: 4000)], available: 300), [100, 200])
    }

    func testLayoutGeometryRejectsNonfiniteMeasurements() {
        let row = RowGeometry(sizes: [CGSize(width: CGFloat.nan, height: 20), CGSize(width: 40, height: CGFloat.infinity)],
                              width: 100, gap: -.infinity, alignment: "stretch", justification: "start", wraps: true)
        XCTAssertEqual(row.size, CGSize(width: 100, height: 20))
        XCTAssertTrue(row.frames.allSatisfy { $0.minX.isFinite && $0.minY.isFinite && $0.width.isFinite && $0.height.isFinite })
        XCTAssertEqual(EqualGridLayout(columns: 0, minimumWidth: nil, gap: 12).columnCount(width: 100), 1)
        XCTAssertEqual(EqualGridLayout(columns: 3, minimumWidth: 120, gap: .nan).columnCount(width: 260), 2)
        XCTAssertEqual(EqualGridLayout(columns: 3, minimumWidth: 120, gap: 12).columnCount(width: .infinity), 3)
        XCTAssertEqual(EqualGridLayout(columns: 3, minimumWidth: .nan, gap: 12).columnCount(width: 260), 3)
    }

    func testLengthsUseFiniteParentProposalsAndRejectPartialValues() {
        XCTAssertEqual(IntelligentUILength.read(.string("50%"))?.resolve(relativeTo: 320, em: 17), 160)
        XCTAssertNil(IntelligentUILength.read(.string("50%"))?.resolve(relativeTo: .infinity, em: 17))
        XCTAssertNil(IntelligentUILength.read(.string("12p")))
        XCTAssertNil(IntelligentUILength.read(.string("-4px")))
        XCTAssertNil(IntelligentUILength.read(.number(.infinity)))
        XCTAssertNil(IntelligentUILength.percent(100).resolve(relativeTo: .greatestFiniteMagnitude, em: 17))
        XCTAssertNil(IntelligentUILength.em(2).resolve(relativeTo: 300, em: .nan))
        XCTAssertEqual(IntelligentUILength.em(2).resolve(relativeTo: 300, em: 24), 48)
        XCTAssertEqual(IntelligentUILength.read(.number(-12)), .points(0))
        XCTAssertEqual(IntelligentUILength.read(.string("25000")), .points(25_000))
        XCTAssertEqual(IntelligentUILength.read(.string(" 1.5px ")), .points(1.5))
        XCTAssertEqual(IntelligentUILength.read(.string("50vw"))?.resolve(relativeTo: 200, em: 17, viewport: CGSize(width: 800, height: 600)), 400)
        XCTAssertEqual(IntelligentUILength.read(.string("25vh"))?.resolve(relativeTo: 200, em: 17, viewport: CGSize(width: 800, height: 600)), 150)
        for invalid in ["-1", ".5px", "1PX", "12pt", "1e2px", "2fr", "calc(50% - 1px)"] {
            XCTAssertNil(IntelligentUILength.read(.string(OpenUIString(invalid))), invalid)
        }
    }

    #if os(macOS)
    @MainActor func testRealBoxFlexFillsRemainderWithShortCopyAtSeveralWidthsAndInRTL() throws {
        let source = """
        root = Row([picture, copy], 2, "start")
        picture = Box([Text("P")], "col", 0, 0, "danger", null, false, 96, 40)
        copy = Box([Text("A")], "col", 0, 0, "success", null, false, null, null, 1)
        """
        for width in [CGFloat(240), 390, 840] {
            for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                try inspectBoxes(source, width: width, direction: direction) { frames in
                    let picture = try XCTUnwrap(frames["danger"])
                    let copy = try XCTUnwrap(frames["success"])
                    XCTAssertEqual(picture.width, 96, accuracy: 1)
                    XCTAssertEqual(copy.width, width - 96 - 8, accuracy: 1)
                    XCTAssertEqual(picture.minY, copy.minY, accuracy: 1)
                    if direction == .leftToRight { XCTAssertEqual(copy.minX - picture.maxX, 8, accuracy: 1) }
                    else { XCTAssertEqual(picture.minX - copy.maxX, 8, accuracy: 1) }
                }
            }
        }
    }

    @MainActor func testRegisteredGridAndCarouselFollowNativeLayoutDirection() throws {
        for container in ["Grid([a,b],2,null,2)", "Carousel([a,b],120,2)"] {
            let source = """
            root = \(container)
            a = Box([], "col", 0, 0, "danger", null, false, null, 40)
            b = Box([], "col", 0, 0, "success", null, false, null, 40)
            """
            for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                try inspectBoxes(source, width: 320, direction: direction) { frames in
                    let a = try XCTUnwrap(frames["danger"]), b = try XCTUnwrap(frames["success"])
                    XCTAssertEqual(a.minY, b.minY, accuracy: 1, container)
                    if direction == .leftToRight { XCTAssertEqual(b.minX - a.maxX, 8, accuracy: 1, container) }
                    else { XCTAssertEqual(a.minX - b.maxX, 8, accuracy: 1, container) }
                }
            }
        }
    }

    @MainActor func testRegisteredColumnsUseNativeLeadingAndTrailingAlignment() throws {
        for alignment in ["start", "end"] {
            let source = """
            root = Box([child], "col", 0, 0, "canvas", null, false, 320, 80, null, "\(alignment)")
            child = Box([], "col", 0, 0, "danger", null, false, 80, 20)
            """
            for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                try inspectBoxes(source, width: 320, direction: direction) { frames in
                    let outer = try XCTUnwrap(frames["canvas"]), child = try XCTUnwrap(frames["danger"])
                    let atPhysicalLeft = (alignment == "start") == (direction == .leftToRight)
                    XCTAssertEqual(child.minX - outer.minX, atPhysicalLeft ? 0 : 240, accuracy: 1)
                    XCTAssertEqual(child.minY, outer.minY, accuracy: 1)
                    XCTAssertEqual(child.width, 80, accuracy: 1)
                }
            }
        }
    }

    @MainActor func testColumnStretchChangesPreserveTheMountedEditor() throws {
        _ = NSApplication.shared
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        defer { state.reset() }
        state.setSource("""
        root = Col([Input($value, "Value", "text", $alignment)], null, $alignment)
        $value = "before"
        $alignment = "start"
        """)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let host = NSHostingView(rootView: OpenIntelligentUIContentView(state: state, library: library)
            .frame(width: 320, height: 160, alignment: .topLeading))
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 160),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.close() }
        func field(_ view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.lazy.compactMap(field).first
        }
        func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
            let deadline = Date().addingTimeInterval(2)
            repeat {
                host.layoutSubtreeIfNeeded()
                if condition() { return }
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            } while Date() < deadline
            XCTAssertTrue(condition(), "The mounted control did not receive its update", file: file, line: line)
        }
        waitUntil { field(host)?.placeholderString == "start" }
        let input = try XCTUnwrap(field(host))
        input.selectText(nil)
        waitUntil { input.currentEditor() != nil }
        let editor = try XCTUnwrap(input.currentEditor() as? NSTextView)
        editor.insertText("edited", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        waitUntil { state.stateValue("$value") == .string("edited") }
        for alignment in ["stretch", "end"] {
            state.setState("$alignment", value: .string(OpenUIString(alignment)))
            waitUntil { field(host)?.placeholderString == alignment }
            XCTAssertTrue(field(host) === input, "Changing width policy must retain the native field")
            XCTAssertTrue(input.currentEditor() === editor, "Changing width policy must retain the active editor")
            XCTAssertEqual(editor.string, "edited")
            XCTAssertEqual(state.stateValue("$value"), .string("edited"))
        }
    }

    @MainActor func testPinnedWrappingRowStillDistributesZeroBasisFlex() throws {
        let source = """
        root = Row([a, b, c], 2, "start", "start", true)
        a = Box([Text("A")], "col", 0, 0, "danger", null, false, null, null, 1)
        b = Box([Text("B")], "col", 0, 0, "success", null, false, null, null, 2)
        c = Box([Text("C")], "col", 0, 0, "info", null, false, null, null, 1)
        """
        try inspectBoxes(source, width: 320) { frames in
            let a = try XCTUnwrap(frames["danger"]), b = try XCTUnwrap(frames["success"])
            let c = try XCTUnwrap(frames["info"])
            XCTAssertEqual(a.width, 76, accuracy: 1)
            XCTAssertEqual(b.width, 152, accuracy: 1)
            XCTAssertEqual(c.width, 76, accuracy: 1)
            XCTAssertEqual(a.minY, b.minY, accuracy: 1)
            XCTAssertEqual(b.minY, c.minY, accuracy: 1)
            XCTAssertEqual(b.minX - a.maxX, 8, accuracy: 1)
            XCTAssertEqual(c.minX - b.maxX, 8, accuracy: 1)
        }
    }

    @MainActor func testPinnedExplicitFlexTakesPriorityOverWidthIncludingZero() throws {
        for (length, expected) in [("96", CGFloat(96)), ("\"50%\"", CGFloat(160))] {
          for (flex, authoredWidth) in [("null", expected), ("0", CGFloat(0)), ("1", CGFloat(156))] {
            let source = """
            root = Row([a, b], 2, "start")
            a = Box([Text("A")], "col", 0, 0, "danger", null, false, \(length), "50%", \(flex))
            b = Box([Text("B")], "col", 0, 0, "success", null, false, null, null, 1)
            """
            for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                try inspectBoxes(source, width: 320, direction: direction) { frames in
                    let a = try XCTUnwrap(frames["danger"]), b = try XCTUnwrap(frames["success"])
                    XCTAssertEqual(a.width, authoredWidth, accuracy: 1)
                    XCTAssertEqual(b.width, 320 - authoredWidth - 8, accuracy: 1)
                    XCTAssertEqual(a.height, b.height, accuracy: 1,
                        "An auto-height row cannot suddenly resolve 50% against the child's own measured height during placement")
                    if direction == .leftToRight { XCTAssertEqual(b.minX - a.maxX, 8, accuracy: 1) }
                    else { XCTAssertEqual(a.minX - b.maxX, 8, accuracy: 1) }
                }
            }
          }
        }
    }

    @MainActor func testRealNonflexCopyShrinksBesideFixedWidthBox() throws {
        let source = """
        root = Row([picture, copy], 2, "start")
        picture = Box([Text("P")], "col", 0, 0, "danger", null, false, 96, 40)
        copy = Box([Text("A long paragraph whose content must wrap beside the fixed image without extending the row.")], "col", 0, 0, "success")
        """
        try inspectBoxes(source, width: 240) { frames in
            let picture = try XCTUnwrap(frames["danger"]), copy = try XCTUnwrap(frames["success"])
            XCTAssertEqual(picture.width, 96, accuracy: 1)
            XCTAssertLessThanOrEqual(copy.width, 137)
            XCTAssertEqual(copy.minX - picture.maxX, 8, accuracy: 1)
            XCTAssertGreaterThan(copy.height, picture.height)
        }
    }

    @MainActor func testRealColumnBoxJustificationUsesItsExplicitHeightAndPadding() throws {
        for (justification, expectedTop) in [("start", CGFloat(12)), ("center", 70), ("end", 128)] {
            let source = """
            root = Box([child], "col", 0, 3, "danger", null, false, 200, 160, null, "start", "\(justification)")
            child = Box([Text("A")], "col", 0, 0, "success", null, false, 40, 20)
            """
            try inspectBoxes(source, width: 320) { frames in
                let outer = try XCTUnwrap(frames["danger"]), child = try XCTUnwrap(frames["success"])
                XCTAssertEqual(outer.height, 160, accuracy: 1)
                XCTAssertEqual(child.minY - outer.minY, expectedTop, accuracy: 1)
                XCTAssertEqual(child.minX - outer.minX, 12, accuracy: 1)
            }
        }
    }

    @MainActor func testRealRowStretchFillsOnlyDirectAutoHeightBoxes() throws {
        let source = """
        root = Row([tall, short, fixed], 2, "stretch")
        tall = Box([Text("T")], "col", 0, 0, "danger", null, false, 80, 80)
        short = Box([inner], "col", 0, 0, "success", null, false, 80)
        inner = Box([Text("i")], "col", 0, 0, "info", null, false, 40)
        fixed = Box([Text("F")], "col", 0, 0, "warning", null, false, 40, 32)
        """
        try inspectBoxes(source, width: 320) { frames in
            let tall = try XCTUnwrap(frames["danger"]), short = try XCTUnwrap(frames["success"])
            let inner = try XCTUnwrap(frames["info"]), fixed = try XCTUnwrap(frames["warning"])
            XCTAssertEqual(tall.height, 80, accuracy: 1)
            XCTAssertEqual(short.height, 80, accuracy: 1)
            XCTAssertEqual(fixed.height, 32, accuracy: 1, "An explicit height wins over stretch")
            XCTAssertLessThan(inner.height, 40, "Stretch must not leak through the direct Box into its children")
            XCTAssertEqual(short.minY, tall.minY, accuracy: 1)
        }
    }

    @MainActor func testRealRowBoxWithExplicitHeightStretchesItsChildren() throws {
        let source = """
        root = Box([a, b], "row", 2, 0, "danger", null, false, 320, 120, null, "stretch")
        a = Box([Text("A")], "col", 0, 0, "success", null, false, 80)
        b = Box([Text("B")], "col", 0, 0, "info", null, false, 80, "50%")
        """
        try inspectBoxes(source, width: 320) { frames in
            let outer = try XCTUnwrap(frames["danger"]), a = try XCTUnwrap(frames["success"])
            let b = try XCTUnwrap(frames["info"])
            XCTAssertEqual(outer.height, 120, accuracy: 1)
            XCTAssertEqual(a.height, 120, accuracy: 1)
            XCTAssertEqual(b.height, 60, accuracy: 1, "A percentage height keeps the explicit parent height as its reference")
            XCTAssertEqual(a.minY, outer.minY, accuracy: 1)
            XCTAssertEqual(b.minY, outer.minY, accuracy: 1)
        }
    }

    @MainActor func testPinnedNumberWidthDoesNotShrinkButPixelStringDoes() throws {
        let source = """
        root = Row([a, b], 2)
        a = Box([Text("A")], "col", 0, 0, "danger", null, false, "96px")
        b = Box([Text("B")], "col", 0, 0, "success", null, false, 96)
        """
        try inspectBoxes(source, width: 128) { frames in
            XCTAssertEqual(try XCTUnwrap(frames["danger"]).width, 24, accuracy: 1)
            XCTAssertEqual(try XCTUnwrap(frames["success"]).width, 96, accuracy: 1)
        }
        try inspectBoxes("root=Box([],\"col\",0,6,\"danger\",null,true,10,10)", width: 320) { frames in
            let box = try XCTUnwrap(frames["danger"])
            XCTAssertEqual(box.width, 50, accuracy: 1)
            XCTAssertEqual(box.height, 50, accuracy: 1)
        }
    }

    @MainActor func testPinnedWrapAllocatesFlexSeparatelyOnEachRow() throws {
        let source = """
        root=Row([a,b,c,d],2,"start","start",true)
        a=Box([Text("A")],"col",0,0,"danger",null,false,160,20)
        b=Box([Text("B")],"col",0,0,"success",null,false,null,null,1)
        c=Box([Text("C")],"col",0,0,"info",null,false,160,20)
        d=Box([Text("D")],"col",0,0,"warning",null,false,null,null,1)
        """
        try inspectBoxes(source, width: 300) { frames in
            let a = try XCTUnwrap(frames["danger"]), b = try XCTUnwrap(frames["success"])
            let c = try XCTUnwrap(frames["info"]), d = try XCTUnwrap(frames["warning"])
            XCTAssertEqual(b.width, 132, accuracy: 1)
            XCTAssertEqual(d.width, 132, accuracy: 1)
            XCTAssertEqual(a.minY, b.minY, accuracy: 1)
            XCTAssertEqual(c.minY, d.minY, accuracy: 1)
            XCTAssertGreaterThan(c.minY, a.minY)
        }
    }

    @MainActor func testPinnedColumnFlexNeedsDefiniteHeightAndKeepsContentMinimums() throws {
        for (flex, expected) in [("1", CGFloat(96)), ("0", CGFloat(20))] {
            let source = """
            root=Box([a,b],"col",2,0,"canvas",null,false,320,200)
            a=Box([mark],"col",0,0,"danger",null,false,null,96,\(flex))
            b=Box([mark],"col",0,0,"success",null,false,null,null,1)
            mark=Box([],"col",0,0,null,null,false,20,20)
            """
            try inspectBoxes(source, width: 320) { frames in
                XCTAssertEqual(try XCTUnwrap(frames["danger"]).height, expected, accuracy: 1)
                XCTAssertEqual(try XCTUnwrap(frames["success"]).height, 192 - expected, accuracy: 1)
            }
        }
        let natural = """
        root=Col([a],0)
        a=Box([mark],"col",0,0,"danger",null,false,null,96,1)
        mark=Box([],"col",0,0,null,null,false,20,20)
        """
        try inspectBoxes(natural, width: 320) { frames in
            let a = try XCTUnwrap(frames["danger"])
            XCTAssertEqual(a.height, 20, accuracy: 1, "Indefinite 0% flex-basis resolves to content, not authored height")
            XCTAssertEqual(a.width, 320, accuracy: 1, "Col defaults to stretch")
        }
    }

    @MainActor func testPinnedColumnWrapDistributesEachColumn() throws {
        let source = """
        root=Box([a,b,c,d],"col",2,0,"canvas",null,false,320,200,null,"stretch","start",true)
        a=Box([],"col",0,0,"danger",null,false,100,120)
        b=Box([mark],"col",0,0,"success",null,false,100,null,1)
        c=Box([],"col",0,0,"info",null,false,100,120)
        d=Box([mark],"col",0,0,"warning",null,false,100,null,1)
        mark=Box([],"col",0,0,null,null,false,20,20)
        """
        try inspectBoxes(source, width: 320) { frames in
            let a = try XCTUnwrap(frames["danger"]), b = try XCTUnwrap(frames["success"])
            let c = try XCTUnwrap(frames["info"]), d = try XCTUnwrap(frames["warning"])
            XCTAssertEqual(a.height, 120, accuracy: 1)
            XCTAssertEqual(c.height, 120, accuracy: 1)
            XCTAssertEqual(b.height, 72, accuracy: 1)
            XCTAssertEqual(d.height, 72, accuracy: 1)
            XCTAssertEqual(b.minY - a.minY, 128, accuracy: 1)
            XCTAssertEqual(c.minX - a.minX, 164, accuracy: 1)
            XCTAssertEqual(c.minY, a.minY, accuracy: 1)
        }
    }

    @MainActor func testFlexAllocationDoesNotLeakThroughCardIntoNestedBox() throws {
        let source = """
        root=Box([Card([inner])],"col",0,0,"canvas",null,false,null,200)
        inner=Box([],"col",0,0,"danger",null,false,60,50)
        """
        try inspectBoxes(source, width: 320) { frames in
            let inner = try XCTUnwrap(frames["danger"])
            XCTAssertEqual(inner.width, 60, accuracy: 1)
            XCTAssertEqual(inner.height, 50, accuracy: 1)
        }
    }

    @MainActor func testPinnedDirectAndSingleBoxPhotosUseDifferentRowOverrides() throws {
        let direct = """
        root=Row([Image("local-photo","direct",2),copy],1,"end")
        copy=Box([Text("Copy")],"col",0,0,"danger",null,false,null,120,1)
        """
        try inspectBoxes(direct, width: 600) { frames in
            let photo = try XCTUnwrap(frames["photo:direct"]), copy = try XCTUnwrap(frames["danger"])
            XCTAssertEqual(photo.width, 198, accuracy: 1)
            XCTAssertEqual(photo.height, 148.5, accuracy: 1)
            XCTAssertEqual(copy.minX - photo.maxX, 16, accuracy: 1)
            XCTAssertEqual(copy.minY, photo.minY, accuracy: 1)
        }
        let boxed = """
        root=Row([picture,copy],1,"end")
        picture=Box([Image("local-photo","wrapped",2)],"col",0,0,"info",null,false,40,null,10)
        copy=Box([Text("Copy")],"col",0,0,"danger",null,false,null,200,1)
        """
        try inspectBoxes(boxed, width: 600) { frames in
            let box = try XCTUnwrap(frames["info"]), photo = try XCTUnwrap(frames["photo:wrapped"])
            let copy = try XCTUnwrap(frames["danger"])
            XCTAssertEqual(box.width, 198, accuracy: 1)
            XCTAssertEqual(photo.height, 148.5, accuracy: 1)
            XCTAssertEqual(copy.minX - box.maxX, 4, accuracy: 1)
            XCTAssertEqual(copy.maxY, box.maxY, accuracy: 1)
        }
    }

    @MainActor func testPinnedRowHeightKeepsPercentageReferenceAcrossWrappingAndOverflow() throws {
        for wraps in ["false", "true"] {
            let source = """
            root=Box([a,b],"row",2,0,"canvas",null,false,320,120,null,"stretch","start",\(wraps))
            a=Box([],"col",0,0,"danger",null,false,80,"50%")
            b=Box([Text("B")],"col",0,0,"success",null,false,80)
            """
            for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                try inspectBoxes(source, width: 320, direction: direction) { frames in
                    XCTAssertEqual(try XCTUnwrap(frames["danger"]).height, 60, accuracy: 1)
                    XCTAssertEqual(try XCTUnwrap(frames["success"]).height, 120, accuracy: 1)
                }
            }
        }
        let overflow = """
        root=Box([a,b,c],"row",2,0,"canvas",null,false,320,120,null,"stretch")
        a=Box([],"col",0,0,"danger",null,false,80,"50%")
        b=Box([],"col",0,0,"info",null,false,80,200)
        c=Box([],"col",0,0,"success",null,false,80)
        """
        try inspectBoxes(overflow, width: 320) { frames in
            XCTAssertEqual(try XCTUnwrap(frames["danger"]).height, 60, accuracy: 1)
            XCTAssertEqual(try XCTUnwrap(frames["info"]).height, 200, accuracy: 1)
            XCTAssertEqual(try XCTUnwrap(frames["success"]).height, 120, accuracy: 1)
        }
        let multiline = """
        root=Box([a,b],"row",2,0,"canvas",null,false,320,120,null,"stretch","start",true)
        a=Box([],"col",0,0,"danger",null,false,200,"50%")
        b=Box([mark],"col",0,0,"success",null,false,200)
        mark=Box([],"col",0,0,null,null,false,20,20)
        """
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            try inspectBoxes(multiline, width: 320, direction: direction) { frames in
                let a = try XCTUnwrap(frames["danger"]), b = try XCTUnwrap(frames["success"])
                XCTAssertEqual(a.height, 60, accuracy: 1)
                XCTAssertEqual(b.height, 36, accuracy: 1)
                XCTAssertEqual(b.minY - a.minY, 84, accuracy: 1)
            }
        }
    }

    @MainActor private func inspectBoxes(_ source: String, width: CGFloat,
        direction: LayoutDirection = .leftToRight, check: ([String: CGRect]) throws -> Void) throws {
        _ = NSApplication.shared
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        defer { state.reset() }
        state.setSource(source)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let measurements = LayoutBoxMeasurements()
        var registry = library.readerComponents.registry
        // Wrap actual registered renderers; all sizing stays in production code.
        for name in ["Box", "Image"] {
            let build = try XCTUnwrap(registry[name])
            registry[name] = { element, currentRegistry in
                let key = name == "Image" ? "photo:" + (PropValue.string(element, "alt") ?? "") : PropValue.string(element, "background") ?? ""
                return AnyView(build(element, currentRegistry).background(GeometryReader { geometry in
                    Color.clear.onAppear { measurements.frames[key] = geometry.frame(in: .global) }
                        .onChange(of: geometry.frame(in: .global)) { measurements.frames[key] = $0 }
                }))
            }
        }
        let host = NSHostingView(rootView: SwiftLangView(state: state, registry: registry)
            .openIntelligentUIImages(["local-photo": Image(systemName: "photo")])
            .environment(\.layoutDirection, direction).environment(\.dynamicTypeSize, .large).frame(width: width))
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: width, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        try check(measurements.frames)
    }
    #endif

    @MainActor func testLayoutProgramAndExpandedParametersRenderAtSeveralWidths() throws {
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        state.setSource(Self.program)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        for width in [240.0, 390.0, 840.0] {
            for size in [DynamicTypeSize.large, .accessibility2] {
                let renderer = ImageRenderer(content: OpenIntelligentUIContentView(state: state, library: library)
                    .environment(\.dynamicTypeSize, size).frame(width: width).padding(12))
                let image = try XCTUnwrap(renderer.cgImage)
                XCTAssertEqual(image.width, Int(width) + 24)
                XCTAssertGreaterThan(image.height, 100)
                XCTAssertLessThan(image.height, 10_000)
            }
        }
    }

    @MainActor func testExtendedSignaturesPreservePositionalArguments() throws {
        let library = try OpenIntelligentUIComponents()
        let state = library.makeState()
        state.setSource("root = Col([Text(\"123\", \"sm\", \"muted\", \"medium\", false, true, true, 2), Image(\"\", \"缺图\", 1, 24, \"contain\"), Button(\"禁用\", @Set($n, 1), \"outline\", \"danger\", \"lg\", \"check\", true, true)])\n$n = 0")
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let children = PropValue.children(try XCTUnwrap(state.root))
        XCTAssertEqual(children[0].props.first { $0.0 == "tabularNums" }?.1, .boolean(true))
        XCTAssertEqual(children[0].props.first { $0.0 == "maxLines" }?.1, .number(2))
        XCTAssertEqual(children[1].props.first { $0.0 == "radius" }?.1, .number(24))
        XCTAssertEqual(children[2].props.first { $0.0 == "disabled" }?.1, .boolean(true))
    }

    func testTextLineLimitHandlesUnboundedAndExtremeValues() {
        XCTAssertNil(TextLineLimit.resolve(nil))
        XCTAssertNil(TextLineLimit.resolve(0))
        XCTAssertNil(TextLineLimit.resolve(.infinity))
        XCTAssertEqual(TextLineLimit.resolve(2.6), 3)
        XCTAssertEqual(TextLineLimit.resolve(Double.greatestFiniteMagnitude), 1000)
    }

    @MainActor func testOfficialFieldAndContainerSignatures() throws {
        let state = try OpenIntelligentUIComponents().makeState()
        state.setSource(#"""
        root = Col([Input($name,"名称","text","旧占位"),TextArea($note,"备注","可选",3),Select($choice,["A","B"],"尺寸","请选择"),Form([Button("提交",@Set($name,"示例"))]),Image("","缺图",1,"md","contain"),Chart("bar",[{x:"A",v:1}],"x",["v"],"number",false,240)])
        $name = ""
        $note = ""
        $choice = "A"
        """#)
        XCTAssertTrue(state.errors.isEmpty, "\(state.errors)")
        let children = PropValue.children(try XCTUnwrap(state.root))
        XCTAssertEqual(PropValue.string(children[0], "placeholder"), "旧占位")
        XCTAssertNil(children[0].props.first { $0.0 == "error" })
        XCTAssertEqual(PropValue.string(children[2], "placeholder"), "请选择")
        XCTAssertEqual(PropValue.children(children[3]).count, 1)
        XCTAssertNil(children[3].props.first { $0.0 == "status" })
        XCTAssertEqual(PropValue.string(children[4], "fit"), "contain")
        XCTAssertNil(children[5].props.first { $0.0 == "selected" })
    }

    private static let program = """
    root = Col([Title("布局与参数验证", "xl", "ink"), Row([Text("第一项"), Text("第二项长文字"), Icon("check"), Text("第三项")], 2, "center", "between", true), Grid([Card([Text("长标题可以自然换行，不裁切信息。")]), Card([Text("第二张卡")]), Card([Text("第三张卡")])], 3, 180, 3), Box([Text("表面与边框"), Image("", "缺少图片", 2, 12, "contain")], "col", 2, 3, "surface", "lg", true), Button("原生按钮", @Set($selected, true), "outline", "success", "lg", "check", false, true)])
    $selected = false
    """
}

#if os(macOS)
private final class LayoutBoxMeasurements {
    var frames: [String: CGRect] = [:]
}
#endif
