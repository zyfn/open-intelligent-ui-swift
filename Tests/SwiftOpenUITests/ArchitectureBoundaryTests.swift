import Foundation
import XCTest

final class ArchitectureBoundaryTests: XCTestCase {
  private var package: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
  }

  private func swiftSources(_ directory: URL) throws -> [(URL, String)] {
    let files = try XCTUnwrap(FileManager.default.enumerator(at: directory,
      includingPropertiesForKeys: nil))
    return try files.compactMap { value in
      guard let url = value as? URL, url.pathExtension == "swift" else { return nil }
      return (url, try String(contentsOf: url, encoding: .utf8))
    }
  }

  private func declarations(named name: String, in sources: [(URL, String)]) throws -> [(URL, String)] {
    let declaration = try NSRegularExpression(pattern:
      #"\b(?:struct|class|enum|protocol)\s+"# + NSRegularExpression.escapedPattern(for: name) + #"\b"#)
    return sources.flatMap { file, source in
      declaration.matches(in: source, range: NSRange(source.startIndex..., in: source))
        .map { _ in (file, source) }
    }
  }

  func testComponentsCannotReachJavaScriptCoreOrLanguageBridgeInternals() throws {
    let root = package.appendingPathComponent("Sources/SwiftOpenUI/Components")
    for (file, source) in try swiftSources(root) {
      XCTAssertNil(source.range(of: #"\b(JSContext|JSValue|JSVirtualMachine|SharedCore)\b|import\s+JavaScriptCore"#,
        options: .regularExpression), file.lastPathComponent)
    }
  }

  func testStandardComponentsCommitAndDispatchThroughTheirContext() throws {
    let root = package.appendingPathComponent("Sources/SwiftOpenUI/Components")
    for (file, source) in try swiftSources(root) {
      XCTAssertNil(source.range(of: #"\bstate\.(perform|triggerAction|setFieldValue|setState)\s*\("#,
        options: .regularExpression), file.lastPathComponent)
    }
  }

  func testMarkdownBackendIsConfinedToTheTextFeature() throws {
    let root = package.appendingPathComponent("Sources/SwiftOpenUI")
    for (file, source) in try swiftSources(root) {
      if source.range(of: #"(?m)^import\s+MarkdownUI\b"#, options: .regularExpression) != nil {
        XCTAssertTrue(file.path.contains("/Components/Text/"), file.path)
      }
    }
  }

  func testPresentationBufferCannotSubmitSourceOrMutateDocumentState() throws {
    let sources = try swiftSources(package.appendingPathComponent("Sources/SwiftOpenUI"))
    let source = try XCTUnwrap(declarations(named: "NativeStreamingTextBuffer", in: sources).first?.1)
    XCTAssertNil(source.range(of:
      #"(?m)^import\s+(SwiftLang|JavaScriptCore)\b|\b(OpenUIState|SharedCore)\b|\b(setSource|setState|triggerAction)\s*\("#,
      options: .regularExpression))
  }

  func testRendererHelpersHaveOneOwnerWithoutCompatibilitySourceCopies() throws {
    let sources = try swiftSources(package.appendingPathComponent("Sources"))
    let owners = [
      ("Sources/SwiftLang/Runtime", ["RenderNode", "RenderValue", "OpenUIRenderChild", "ElementErrorBoundary"]),
      ("Sources/SwiftOpenUI/Components/Text", ["NativeMarkdownText", "NativeStreamingTextBuffer",
        "NativeMathRenderer", "NativeCodeBlock", "CardSourceProvider"]),
    ]
    for (directory, names) in owners {
      for name in names {
        let matches = try declarations(named: name, in: sources)
        XCTAssertEqual(matches.count, 1, name)
        for (file, _) in matches {
          XCTAssertTrue(file.path.hasPrefix(package.appendingPathComponent(directory).path + "/"), file.path)
        }
      }
    }
  }

  func testPresentationJavaScriptIsConfinedToTypedInternalAdapters() throws {
    let root = package.appendingPathComponent("Sources/SwiftOpenUI")
    let sources = try swiftSources(root)
    let adapters = try ["NativeRichTextEngine", "NativeCodeSyntax"].map { name in
      let matches = try declarations(named: name, in: sources)
      XCTAssertEqual(matches.count, 1, name)
      let file = try XCTUnwrap(matches.first?.0)
      XCTAssertTrue(file.path.hasPrefix(root.appendingPathComponent("Internal").path + "/"), file.path)
      return file
    }
    let bridgeFiles = sources.filter {
      $0.1.range(of: #"\bimport\s+JavaScriptCore\b"#, options: .regularExpression) != nil
    }
    XCTAssertEqual(Set(bridgeFiles.map { $0.0 }), Set(adapters))
  }
}
