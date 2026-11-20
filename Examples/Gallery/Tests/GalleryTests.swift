import Foundation
import SwiftLang
import SwiftOpenUI
import SwiftUI
import XCTest
@testable import OpenUIGallery

#if os(macOS)
import AppKit
#endif

final class GalleryTests: XCTestCase {
    func testScenesUseConcreteUserTaskTypesForBothProducts() throws {
        let scenes = try GalleryCatalog(resourceRoot: GalleryResources.root()).entries.filter { $0.section == .cases }
        XCTAssertEqual(scenes.count, 10)
        XCTAssertEqual(Set(scenes.map { $0.item.category }),
                       Set(["旅行出行", "家居设计", "购物选购", "学习理解", "账单分析", "信息填写"]))
        XCTAssertEqual(scenes.filter { $0.item.category == "旅行出行" }.count, 4)
        XCTAssertEqual(scenes.first { $0.item.id == "transport-comparison" }?.item.category, "旅行出行")
        XCTAssertEqual(scenes.first { $0.item.id == "bedroom-style" }?.item.category, "家居设计")
        XCTAssertEqual(scenes.first { $0.item.id == "desk-lamp" }?.item.category, "购物选购")
        for product in GalleryLibrary.allCases {
            XCTAssertEqual(scenes.filter { $0.supports(product) }.count, scenes.count)
        }
    }

    func testSidebarExpansionIsIndependentPerProductAndSurvivesRepeatedToggles() {
        var navigation = GallerySidebarState()
        navigation.toggle(.controls, in: .openUI)
        XCTAssertTrue(navigation.isExpanded(.controls, in: .openUI))
        XCTAssertFalse(navigation.isExpanded(.controls, in: .openIntelligentUI))
        navigation.toggle(.controls, in: .openIntelligentUI)
        for _ in 0..<3 {
            navigation.toggle(.controls, in: .openUI)
            XCTAssertFalse(navigation.isExpanded(.controls, in: .openUI))
            XCTAssertTrue(navigation.isExpanded(.controls, in: .openIntelligentUI))
            navigation.toggle(.controls, in: .openUI)
            XCTAssertTrue(navigation.isExpanded(.controls, in: .openUI))
        }
    }

    private func catalogData(programs: [String: String], duplicate: Bool = false) throws -> Data {
        let item: [String: Any] = ["id": "case", "title": "Case", "summary": "Summary", "category": "Test",
                                  "tags": [], "programs": programs]
        return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "cases": duplicate ? [item, item] : [item]])
    }

    func testCatalogRejectsMixedLibrariesEscapedPathsAndDuplicateIDs() throws {
        let valid = ["openui": "openui/case.openui", "openintelligentui": "openintelligentui/case.openui"]
        XCTAssertEqual(try GalleryCatalog.decode(catalogData(programs: valid), requiringBothLibraries: true).count, 1)
        XCTAssertThrowsError(try GalleryCatalog.decode(catalogData(programs: ["future": "future/case.openui"]), requiringBothLibraries: false))
        XCTAssertThrowsError(try GalleryCatalog.decode(catalogData(programs: ["openui": "openui/case.openui"]), requiringBothLibraries: true))
        XCTAssertThrowsError(try GalleryCatalog.decode(catalogData(programs: valid, duplicate: true), requiringBothLibraries: true))
        for path in ["../case.openui", "/case.openui", "openui/../case.openui", "standard\\case.openui"] {
            XCTAssertThrowsError(try GalleryCatalog.decode(catalogData(programs: ["openui": path]), requiringBothLibraries: false))
        }
    }

    func testExternalProgramRequiresExplicitLibraryAndValidViewport() throws {
        for removedName in ["standard", "intelligent"] {
            XCTAssertThrowsError(try GalleryOptions.parse(["--library", removedName]))
        }
        XCTAssertThrowsError(try GalleryOptions.parse(["--program", "example.openui"]))
        XCTAssertThrowsError(try GalleryOptions.parse(["--library", "unknown"]))
        XCTAssertThrowsError(try GalleryOptions.parse(["--unknown"]))
        XCTAssertThrowsError(try GalleryOptions.parse(["--stream-suffix", "tail.openui"]))
        XCTAssertThrowsError(try GalleryOptions.parse(["--zoom", "nan"]))
        XCTAssertThrowsError(try GalleryOptions.parse(["--width", "40"]))
        let options = try GalleryOptions.parse(["--program", "example.json", "--library", "openui", "--width", "768", "--height", "1024", "--zoom", "0.75"])
        XCTAssertEqual(options.library, .openUI)
        XCTAssertEqual(options.width, 768)
        XCTAssertEqual(options.height, 1024)
        XCTAssertEqual(options.zoom, 0.75)
        XCTAssertEqual(try GalleryOptions.parse(["--library", "openui"]).library, .openUI)
        XCTAssertEqual(try GalleryOptions.parse(["--library", "openintelligentui"]).library, .openIntelligentUI)
    }

    func testJSONImportChecksLibraryAndPreservesUTF8Source() throws {
        let source = #"root = Col([Text("原始内容 🧭")])"#
        let json = try JSONSerialization.data(withJSONObject: ["program": source, "library": "openintelligentui"])
        let text = try XCTUnwrap(String(data: json, encoding: .utf8))
        XCTAssertEqual(try GalleryImportedProgram.decode(text, isJSON: true, library: .openIntelligentUI), source)
        XCTAssertThrowsError(try GalleryImportedProgram.decode(text, isJSON: true, library: .openUI))
        XCTAssertThrowsError(try GalleryImportedProgram.decode("{}", isJSON: true, library: .openIntelligentUI))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("record.txt")
        try json.write(to: file)
        XCTAssertEqual(try GalleryImportedProgram.read(url: file, library: .openIntelligentUI), source)
        try Data([0xff]).write(to: file)
        XCTAssertThrowsError(try GalleryImportedProgram.read(url: file, library: .openIntelligentUI))
    }

    @MainActor func testChangingCaseOrLibraryRetiresTheOldDocumentAndItsState() throws {
        let model = GalleryModel()
        XCTAssertNil(model.failure)
        let entries = model.entries.filter { $0.section == .cases }
        XCTAssertGreaterThan(entries.count, 1)
        model.select(entries[0].id)
        let first = try XCTUnwrap(model.session)
        first.state.setState("$gallerySentinel", value: .string("edited"))
        model.select(entries[1].id)
        let second = try XCTUnwrap(model.session)
        XCTAssertFalse(first.state === second.state)
        XCTAssertNil(first.state.root)
        XCTAssertNil(second.state.snapshotState()["$gallerySentinel"])
        model.selectLibrary(.openUI)
        let standard = try XCTUnwrap(model.session)
        XCTAssertEqual(model.selectedID, entries[1].id)
        XCTAssertFalse(second.state === standard.state)
        XCTAssertNil(second.state.root)
        XCTAssertEqual(standard.kind, .openUI)
        XCTAssertEqual(standard.state.root?.typeName, "Stack")
        standard.retire()
    }

    @MainActor func testPauseResumeAndRetirementDoNotAllowLateStreamingWrites() async throws {
        let source = "root = Col([Text(\"" + String(repeating: "流式文字", count: 100) + "\")])"
        let session = try GalleryDocumentSession(kind: .openIntelligentUI, source: source, title: "Stream")
        var updates = 0
        session.state.onParseResult = { _ in updates += 1 }
        session.stream(chunkSize: 24, intervalNanoseconds: 2_000_000)
        await eventually { updates >= 2 }
        session.pause()
        let pausedUpdates = updates
        try await Task.sleep(nanoseconds: 15_000_000)
        XCTAssertEqual(updates, pausedUpdates)
        XCTAssertEqual(session.playback, .paused)
        XCTAssertFalse(session.state.isComplete)
        session.resume(chunkSize: 80, intervalNanoseconds: 1_000_000)
        await eventually { session.playback == .complete }
        XCTAssertTrue(session.state.isComplete)
        XCTAssertTrue(session.state.errors.isEmpty)
        session.stream(chunkSize: 1, intervalNanoseconds: 2_000_000)
        await eventually { session.playback == .streaming }
        session.retire()
        let retiredUpdates = updates
        try await Task.sleep(nanoseconds: 15_000_000)
        XCTAssertEqual(updates, retiredUpdates)
        XCTAssertNil(session.state.root)
    }

    @MainActor func testProductSwitchReplacesComponentCatalogAndRestoresEachSelection() throws {
        let model = GalleryModel()
        XCTAssertNil(model.failure)
        let intelligent = try XCTUnwrap(model.components.first { $0.name == "ProductCard" })
        model.select(intelligent.id)
        let previous = try XCTUnwrap(model.session)
        model.selectLibrary(.openUI)
        XCTAssertNil(model.failure)
        XCTAssertFalse(model.components.contains { $0.name == "ProductCard" })
        XCTAssertNil(previous.state.root)
        let openUI = try XCTUnwrap(model.components.first { $0.name == "VisualCardBlock" })
        model.select(openUI.id)
        model.selectLibrary(.openIntelligentUI)
        XCTAssertEqual(model.selectedID, intelligent.id)
        XCTAssertEqual(model.session?.kind, .openIntelligentUI)
        model.selectLibrary(.openUI)
        XCTAssertEqual(model.selectedID, openUI.id)
        XCTAssertEqual(model.session?.kind, .openUI)
        model.session?.retire()
        let direct = GalleryModel(options: try GalleryOptions.parse(["--library", "openui", "--case", "Components/Button"]))
        XCTAssertNil(direct.failure)
        XCTAssertEqual(direct.selectedComponent?.name, "Button")
        direct.session?.retire()
    }

    @MainActor func testEveryRegisteredComponentHasAMatchingExampleAndEvaluates() throws {
        let root = try GalleryResources.root()
        for kind in GalleryLibrary.allCases {
            let library = try kind.makeLibrary()
            let items = try GalleryComponent.load(kind, resourceRoot: root)
            XCTAssertEqual(Set(items.map(\.name)), Set(library.specification.components.map(\.name)))
            let rows = GalleryComponentRow.hierarchy(items)
            XCTAssertEqual(rows.count, items.count)
            XCTAssertEqual(Set(rows.map(\.id)), Set(items.map(\.id)))
            if kind == .openUI {
                XCTAssertEqual(items.count, 88)
                XCTAssertTrue(items.contains { $0.name == "JourneyLine" })
                XCTAssertEqual(items.first { $0.name == "Steps" }?.category, .layout)
                XCTAssertEqual(items.first { $0.name == "Card" }?.category, .content)
                XCTAssertEqual(items.first { $0.name == "EntityList" }?.category, .data)
                let categories = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.category) })
                for name in ["Table", "BarChart", "PieChart", "ScatterChart"] {
                    XCTAssertEqual(categories[name], .tablesAndCharts, name)
                }
                for name in ["Form", "Button", "FollowUpBlock"] {
                    XCTAssertEqual(categories[name], .formsAndButtons, name)
                }
                XCTAssertEqual(Set(categories.values).count, 7)
                XCTAssertEqual(items.first { $0.name == "StepsItem" }?.container, "Steps")
                XCTAssertEqual(items.first { $0.name == "Point" }?.container, "ScatterSeries")
            } else {
                XCTAssertEqual(items.first { $0.name == "Card" }?.category, .layout)
                XCTAssertEqual(items.first { $0.name == "Flashcard" }?.category, .content)
            }
            for (index, row) in rows.enumerated() {
                let item = row.component
                let example = try XCTUnwrap(item.examples.first, item.id)
                let state = library.makeState()
                state.setSource(example.program)
                XCTAssertTrue(example.program.contains(item.name + "("), item.id)
                let root = try XCTUnwrap(state.root, item.id)
                if let container = item.container {
                    let parent = try XCTUnwrap(rows[..<index].last { $0.component.name == container }, item.id)
                    XCTAssertEqual(row.depth, parent.depth + 1, item.id)
                    XCTAssertEqual(item.examples, parent.component.examples, item.id)
                    XCTAssertEqual(item.category, parent.component.category, item.id)
                    XCTAssertTrue(GalleryValidation.contains(item.name, in: container, root: root), item.id)
                }
                if item.name == "Series" {
                    XCTAssertEqual(item.category, .tablesAndCharts)
                    XCTAssertNil(item.container)
                    XCTAssertTrue(item.supporting)
                    XCTAssertTrue(GalleryValidation.contains("Series", in: "BarChart", root: root))
                    XCTAssertTrue(GalleryValidation.contains("Series", in: "LineChart", root: root))
                }
                XCTAssertTrue(state.errors.isEmpty, item.id + ": " + state.errors.map(\.message).joined(separator: "; "))
                state.reset()
            }
        }
    }

    @MainActor func testSelectingStepsItemKeepsTheParentPreviewAndEdits() throws {
        let options = try GalleryOptions.parse(["--library", "openui", "--case", "Components/Steps"])
        let model = GalleryModel(options: options)
        let preview = try XCTUnwrap(model.session)
        defer { preview.retire() }
        preview.draft += "\n"
        let draft = preview.draft

        model.select("Components/StepsItem")
        XCTAssertEqual(model.selectedComponent?.name, "StepsItem")
        XCTAssertTrue(model.session === preview)
        XCTAssertEqual(model.session?.draft, draft)
        XCTAssertNil(model.failure)
    }

    @MainActor func testSwitchingUsageRetiresThePreviousProgramAndKeepsSelectionInItsFamily() throws {
        let options = try GalleryOptions.parse(["--library", "openui", "--case", "Components/Steps"])
        let model = GalleryModel(options: options)
        let previous = try XCTUnwrap(model.session)
        XCTAssertEqual(model.selectedExampleID, "number")
        model.selectExample("timeline")
        let timeline = try XCTUnwrap(model.session)
        XCTAssertEqual(model.selectedExampleID, "timeline")
        XCTAssertNil(previous.state.root)
        XCTAssertTrue(GalleryValidation.contains("StepsItem", in: "Steps", root: try XCTUnwrap(timeline.state.root)))
        model.select("Components/StepsItem")
        XCTAssertTrue(model.session === timeline)
        XCTAssertEqual(model.selectedExampleID, "timeline")
        model.select("Components/Card")
        XCTAssertNil(timeline.state.root)
        XCTAssertEqual(model.selectedExampleID, "appearance")
        model.session?.retire()
    }

    @MainActor func testDesignSystemShowsMuseTokensAndIsSharedAcrossProducts() throws {
        let options = try GalleryOptions.parse(["--library", "openui", "--case", "DesignSystem"])
        let model = GalleryModel(options: options)
        let design = try XCTUnwrap(model.designSystem)
        let base = design.tokens(for: .original)
        let sphere = design.tokens(for: .liquidSphere)
        XCTAssertEqual(model.selectedID, GalleryDesignSystem.id)
        XCTAssertNil(model.session)
        XCTAssertEqual(base.colors.count, 17)
        XCTAssertEqual(Set(sphere.colors.keys), Set(base.colors.keys))
        XCTAssertEqual(base.typography.count, 7)
        XCTAssertEqual(base.spacing.count, 15)
        XCTAssertEqual(base.colorValue("accent", scheme: .light)?.hex, "#126BF8")
        XCTAssertEqual(sphere.colorValue("accent", scheme: .light)?.hex, "#000000")
        XCTAssertEqual(sphere.colorValue("canvas", scheme: .dark)?.hex, base.colorValue("canvas", scheme: .dark)?.hex)
        let original = base.openUITheme(.original, scheme: .light).resolved()
        let liquid = sphere.openUITheme(.liquidSphere, scheme: .light).resolved()
        XCTAssertEqual(original.textHeadingMd.size, 25)
        XCTAssertEqual(liquid.textHeadingMd.size, 20)
        XCTAssertEqual(original.radius3xl, 16)
        XCTAssertEqual(liquid.radius3xl, 20)
        XCTAssertEqual(original.tableAppearance?.cornerRadius, 16)
        XCTAssertEqual(liquid.tableAppearance?.cornerRadius, 20)
        XCTAssertEqual(original.imagePlaceholderBackground, OpenUITheme().resolved().imagePlaceholderBackground)
        XCTAssertEqual(original.textCodeDefault, OpenUIThemeValues().textCodeDefault)
        XCTAssertEqual(original.shadowL, OpenUIThemeValues().shadowL)
        XCTAssertEqual(sphere.spacing["spaceML"], base.spacing["spaceML"])
        model.selectLibrary(.openIntelligentUI)
        XCTAssertEqual(model.selectedID, GalleryDesignSystem.id)
        XCTAssertNil(model.session)
    }

    @MainActor func testComponentMarksPersistAndPreserveAnotherLibraryMark() throws {
        let repository = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = repository.appendingPathComponent("Examples/Gallery/Resources/" + GalleryComponentMarks.resourcePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repository) }
        try Data(#"{"openui":[],"openintelligentui":[]}"#.utf8).write(to: file)
        let options = try GalleryOptions.parse(["--library", "openui", "--case", "Components/StepsItem"])
        let model = GalleryModel(options: options)
        let preview = try XCTUnwrap(model.session)
        defer { preview.retire() }
        model.connectMarksRepository(repository)

        model.setComponentMarked(true, name: "StepsItem", library: .openUI)
        XCTAssertNil(model.marksFailure)
        XCTAssertTrue(model.componentMarks.contains("StepsItem", in: .openUI))
        XCTAssertFalse(model.componentMarks.contains("Steps", in: .openUI))
        XCTAssertTrue(model.session === preview)
        XCTAssertTrue(try GalleryComponentMarks.read(in: repository).contains("StepsItem", in: .openUI))

        _ = try GalleryComponentMarks.set(true, component: "ListItem", library: .openIntelligentUI, in: repository)
        model.setComponentMarked(false, name: "StepsItem", library: .openUI)
        XCTAssertNil(model.marksFailure)
        let saved = try GalleryComponentMarks.read(in: repository)
        XCTAssertFalse(saved.contains("StepsItem", in: .openUI))
        XCTAssertTrue(saved.contains("ListItem", in: .openIntelligentUI))
        XCTAssertTrue(model.session === preview)
    }

    func testIntelligentScenesKeepOriginalMediaLinksAndEssentialReadingSections() throws {
        let catalog = try GalleryCatalog(resourceRoot: GalleryResources.root())
        let urlPattern = try NSRegularExpression(pattern: #""(https://[^"\s]+)""#)
        let anchors = [
            "scene-discovery": ["四种周末，各有自己的节奏", "先选一种喜欢的感觉"],
            "hangzhou-weekend": ["Day 01｜南宋临安", "Day 02｜西湖文脉", "门票与预约", "现场氛围，一眼对比"],
            "heat-pump": ["0℃", "−15℃", "室内放热", "COP", "一句话总结"],
            "bedroom-style": ["可多选", "舒服，不一定需要重新装修", "preferences:selected"],
            "desk-lamp": ["三款台灯候选", "971628097659", "1014479690931", "1087331917809", "2026-11-10"],
            "code-isolation": ["125ms", "Guest Kernel", "Warm Pool", "runtimeClassName", "按现有条件选型"],
            "suzhou-family": ["Day 01｜园林与平江水巷", "Day 02｜留园与山塘旧街", "¥1,180", "15:00", "父母"],
            "transport-comparison": ["2 小时 55 分", "arrivalDayOffset:1", "changeStation:true", "历史记录"],
            "monthly-spending": ["¥18,000", "¥6,600", "¥6,000", "$period"],
            "contact-form": ["$reviewed==snapshot", "内容已修改，请重新核对", "姓名 · 必填", "邮箱 · 必填"]
        ]
        for entry in catalog.entries where entry.section == .cases {
            let original = try entry.source(for: .openUI)
            let intelligent = try entry.source(for: .openIntelligentUI)
            for match in urlPattern.matches(in: original, range: NSRange(original.startIndex..., in: original)) {
                let range = try XCTUnwrap(Range(match.range(at: 1), in: original))
                XCTAssertTrue(intelligent.contains(original[range]), entry.id + " dropped a source media/link URL")
            }
            for anchor in try XCTUnwrap(anchors[entry.item.id]) {
                XCTAssertTrue(intelligent.contains(anchor), entry.id + " lost section or source fact: " + anchor)
            }
        }
    }

    @MainActor func testHangzhouMapKeepsAllCategorizedMarkersWithoutSceneLevelFiltering() throws {
        let catalog = try GalleryCatalog(resourceRoot: GalleryResources.root())
        let entry = try XCTUnwrap(catalog.entries.first { $0.item.id == "hangzhou-weekend" })
        let source = try entry.source(for: .openIntelligentUI)
        XCTAssertFalse(source.contains("$mapDay"), "Filtering belongs to the map component")
        let state = try GalleryLibrary.openIntelligentUI.makeLibrary().makeState()
        state.setSource(source)
        func maps(in value: Value) -> [EvaluatedElement] {
            switch value {
            case .element(let element):
                if element.typeName == "Map" { return [element] }
                return element.props.flatMap { maps(in: $0.1) }
            case .array(let values): return values.flatMap { maps(in: $0) }
            default: return []
            }
        }
        let map = try XCTUnwrap(maps(in: .element(try XCTUnwrap(state.root))).first)
        guard case .array(let markers) = map.props.first(where: { $0.0 == "markers" })?.1 else {
            return XCTFail("Map markers must remain a native element array")
        }
        XCTAssertEqual(markers.count, 7)
        var categories: [String: Int] = [:]
        for marker in markers {
            guard case .element(let point) = marker else { return XCTFail("MapMarker was converted into plain data") }
            XCTAssertEqual(point.typeName, "MapMarker")
            guard case .string(let category) = point.props.first(where: { $0.0 == "category" })?.1 else {
                return XCTFail("The map needs original category data")
            }
            categories[category.displayString, default: 0] += 1
            for field: OpenUIString in ["lat", "lng"] {
                guard case .number(let coordinate) = point.props.first(where: { $0.0 == field })?.1 else {
                    return XCTFail("Missing coordinate")
                }
                XCTAssertTrue(coordinate.isFinite)
            }
        }
        XCTAssertEqual(categories, ["第一天": 3, "第二天": 3, "补充地点": 1])
        state.reset()
    }

    @MainActor func testSuffixRestoreInterruptAndCompleteAlwaysKeepTheWholeProgram() throws {
        let prefix = "root = Stack([TextContent(\"未闭合"
        let suffix = "字符串\")])"
        let whole = prefix + suffix
        let restored = try GalleryDocumentSession(kind: .openUI, source: prefix, title: "Suffix", suffix: suffix)
        XCTAssertEqual(restored.draft, whole)
        XCTAssertFalse(restored.state.isComplete)
        restored.restore()
        XCTAssertTrue(restored.state.isComplete)
        XCTAssertTrue(restored.state.errors.isEmpty)
        XCTAssertEqual(restored.draft, whole)
        restored.retire()

        let interrupted = try GalleryDocumentSession(kind: .openUI, source: prefix, title: "Suffix", suffix: suffix)
        interrupted.interrupt()
        XCTAssertTrue(interrupted.state.isInterrupted)
        XCTAssertNil(interrupted.pendingSuffix)
        XCTAssertEqual(interrupted.draft, whole)
        interrupted.render()
        XCTAssertFalse(interrupted.state.isInterrupted)
        XCTAssertTrue(interrupted.state.errors.isEmpty)
        interrupted.retire()

        let appended = try GalleryDocumentSession(kind: .openUI, source: prefix, title: "Suffix", suffix: suffix)
        appended.appendSuffix()
        XCTAssertEqual(appended.draft, whole, "Appending the preview suffix must not duplicate it in the editor")
        XCTAssertTrue(appended.state.errors.isEmpty)
        appended.retire()
    }

    @MainActor func testRawStreamSuffixMayStartWithAnObjectLiteral() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("suffix.openui")
        let suffix = "{title: \"Lamp\"}]\nroot = Stack([TextContent(items[0].title)])"
        try suffix.write(to: url, atomically: true, encoding: .utf8)
        let raw = try GalleryImportedProgram.readRaw(url: url)
        XCTAssertEqual(raw, suffix)
        let session = try GalleryDocumentSession(kind: .openUI, source: "items = [", title: "Raw suffix", suffix: raw)
        session.appendSuffix()
        XCTAssertTrue(session.state.errors.isEmpty)
        XCTAssertNotNil(session.state.root)
        session.retire()
    }

    @MainActor func testLocalQueryDiagnosticUpdatesItsDependentResultInBothLibraries() async throws {
        let catalog = try GalleryCatalog(resourceRoot: GalleryResources.root())
        let entry = try XCTUnwrap(catalog.entries.first { $0.item.id == "query-chain" })
        for kind in GalleryLibrary.allCases {
            let session = try GalleryDocumentSession(kind: kind, source: entry.source(for: kind), title: "Queries")
            await eventually { self.queryValue(session) == .number(1) }
            session.state.runQuery(statementId: "seed", tool: "gallery.seed", args: .object([]),
                                   defaults: .object([ObjectField(key: "value", value: .number(0))]))
            await eventually { self.queryValue(session) == .number(2) }
            XCTAssertTrue(session.state.errors.isEmpty)
            session.retire()
        }
    }

    func testBundledImageMatchesItsExactSourceAndFailureStaysLocal() async throws {
        let root = try GalleryResources.root()
        let loader = try GalleryImageLoader(resourceRoot: root)
        let request = try XCTUnwrap(loader.request(for: GalleryImageLoader.cameraURL, relativeTo: nil))
        let data = try await loader.data(for: request)
        XCTAssertEqual(data, try Data(contentsOf: root.appendingPathComponent("Images/nikon-front.jpg")))
        let missing = try XCTUnwrap(loader.request(for: "https://gallery.invalid/missing.jpg", relativeTo: nil))
        do { _ = try await loader.data(for: missing); XCTFail("The diagnostic request must fail locally") }
        catch { XCTAssertTrue(error is GalleryFailure) }
    }

    #if os(macOS)
    @MainActor func testNativePreviewResizingAndZoomingKeepEditedStateAndSourceRevision() throws {
        _ = NSApplication.shared
        let session = try GalleryDocumentSession(kind: .openUI,
            source: "root = Stack([TextContent($value)])\n$value = \"original\"", title: "Viewport")
        session.state.setState("$value", value: .string("edited"))
        let revision = session.state.sourceRevision
        func preview(_ viewport: GalleryViewport) -> GalleryPreview {
            GalleryPreview(session: session, resources: .init(), viewport: viewport,
                           dynamicType: .large, locale: Locale(identifier: "en"), direction: .leftToRight,
                           museTheme: .original, tokens: nil)
        }
        let host = NSHostingView(rootView: preview(.init(width: 390, height: 844, zoom: 1)))
        host.frame = CGRect(x: 0, y: 0, width: 900, height: 1000)
        host.layoutSubtreeIfNeeded()
        host.rootView = preview(.init(width: 768, height: 1024, zoom: 0.5))
        host.layoutSubtreeIfNeeded()
        host.rootView = preview(.init(width: 320, height: 568, zoom: 1.5))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(session.state.sourceRevision, revision)
        XCTAssertEqual(session.state.stateValue("$value"), .string("edited"))
        XCTAssertEqual(session.playback, .complete)
        session.retire()
    }
    #endif

    @MainActor private func queryValue(_ session: GalleryDocumentSession) -> Value? {
        guard case .object(let result) = session.state.queryStates["details"]?.data else { return nil }
        return result["value"]
    }

    @MainActor private func eventually(_ condition: () -> Bool) async {
        for _ in 0..<300 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Gallery operation did not complete")
    }
}
