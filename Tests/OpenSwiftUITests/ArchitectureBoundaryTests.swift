import OpenUICore
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

  func testLanguageRuntimeDoesNotDependOnNativePresentation() throws {
    let root = package
    for (file, source) in try swiftSources(root.appendingPathComponent("Sources/OpenUILang")) {
      XCTAssertNil(source.range(of: #"(?m)^import\s+(SwiftUI|UIKit|AppKit|OpenUICore|OpenSwiftUI|OpenIntelligentSwiftUI)\b"#,
        options: .regularExpression), file.lastPathComponent)
    }
    let manifest = try String(contentsOf: package.appendingPathComponent("Package.swift"), encoding: .utf8)
    XCTAssertTrue(manifest.contains(#".target(name: "OpenUILang", dependencies: ["COpenUIRegExp"]"#))
    XCTAssertFalse(manifest.contains("https://github.com/zyfn/openui.git"))
  }

  func testComponentsCannotReachJavaScriptCoreOrLanguageBridgeInternals() throws {
    let root = package.appendingPathComponent("Sources/OpenSwiftUI/Components")
    for (file, source) in try swiftSources(root) {
      XCTAssertNil(source.range(of: #"\b(JSContext|JSValue|JSVirtualMachine|SharedCore)\b|import\s+JavaScriptCore"#,
        options: .regularExpression), file.lastPathComponent)
    }
  }

  func testStandardComponentsCommitAndDispatchThroughTheirContext() throws {
    let root = package.appendingPathComponent("Sources/OpenSwiftUI/Components")
    for (file, source) in try swiftSources(root) {
      XCTAssertNil(source.range(of: #"\bstate\.(perform|triggerAction|setFieldValue|setState)\s*\("#,
        options: .regularExpression), file.lastPathComponent)
    }
  }

  func testMarkdownBackendIsConfinedToTheTextFeature() throws {
    let root = package.appendingPathComponent("Sources/OpenSwiftUI")
    for (file, source) in try swiftSources(root) {
      if source.range(of: #"(?m)^import\s+MarkdownUI\b"#, options: .regularExpression) != nil {
        XCTAssertTrue(file.path.contains("/Components/Text/"), file.path)
      }
    }
  }

  func testPresentationBufferCannotSubmitSourceOrMutateDocumentState() throws {
    let file = package.appendingPathComponent(
      "Sources/OpenSwiftUI/Components/Text/NativeStreamingTextBuffer.swift")
    let source = try String(contentsOf: file, encoding: .utf8)
    XCTAssertNil(source.range(of:
      #"(?m)^import\s+(OpenUILang|JavaScriptCore)\b|\b(OpenUIState|SharedCore)\b|\b(setSource|setState|triggerAction)\s*\("#,
      options: .regularExpression))
  }

  func testRendererHelpersHaveOneOwnerWithoutCompatibilitySourceCopies() throws {
    let root = package.appendingPathComponent("Sources/OpenSwiftUI")
    let node = try String(contentsOf: package.appendingPathComponent("Sources/OpenUICore/RenderNode.swift"), encoding: .utf8)
    for name in ["RenderNode", "RenderValue", "OpenUIRenderChild", "ElementErrorBoundary"] {
      XCTAssertTrue(node.contains("struct " + name), name)
    }
    for oldPath in ["RenderNode.swift", "RenderValue.swift", "Internal/RenderIdentity.swift", "ErrorBoundary.swift"] {
      XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(oldPath).path), oldPath)
    }
    for name in ["NativeMarkdownText", "NativeStreamingTextBuffer", "NativeMath", "NativeCodeBlock", "CardSourceProvider"] {
      XCTAssertTrue(FileManager.default.fileExists(atPath:
        root.appendingPathComponent("Components/Text/" + name + ".swift").path), name)
      XCTAssertFalse(FileManager.default.fileExists(atPath:
        root.appendingPathComponent("Components/" + name + ".swift").path), name)
    }
  }

  func testNativePackageExportsFourModulesWithoutAChatShell() throws {
    let manifest = try String(contentsOf: package.appendingPathComponent("Package.swift"), encoding: .utf8)
    XCTAssertEqual(manifest.components(separatedBy: ".library(").count - 1, 4)
    XCTAssertTrue(manifest.contains(#"name: "OpenSwiftUI""#))
    XCTAssertTrue(manifest.contains(#"name: "OpenIntelligentSwiftUI""#))
    for forbidden in ["react-headless", "react-ui", "DocumentRuntime", "ChatRuntime"] {
      XCTAssertFalse(manifest.contains(forbidden), forbidden)
    }
  }

  func testPresentationJavaScriptIsConfinedToTypedInternalAdapters() throws {
    let root = package.appendingPathComponent("Sources/OpenSwiftUI")
    let bridgeFiles = try swiftSources(root).filter { $0.1.contains("import JavaScriptCore") }
    XCTAssertEqual(Set(bridgeFiles.map { $0.0.lastPathComponent }),
      ["NativeRichText.swift", "NativeCodeSyntax.swift"])
    XCTAssertTrue(bridgeFiles.allSatisfy { $0.0.deletingLastPathComponent().lastPathComponent == "Internal" })
  }
}
