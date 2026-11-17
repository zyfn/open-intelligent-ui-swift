#if os(macOS)
import AppKit
import ApplicationServices
import XCTest

@MainActor
enum NativeAccessibilityTestSupport {
    static let application: NSApplication = {
        let application = NSApplication.shared
        application.finishLaunching()
        return application
    }()

    static func activate(in host: NSView, file: StaticString = #filePath, line: UInt = #line) async throws {
        _ = application
        host.layoutSubtreeIfNeeded()
        // SwiftUI creates virtual accessibility nodes lazily. Ask the current
        // test process for its application role without holding the main actor,
        // so AppKit can answer. This does not change accessibility permissions.
        let request = await Task.detached {
            let onMain = Thread.isMainThread
            let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            var role: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(application, kAXRoleAttribute as CFString, &role)
            return (onMain: onMain, code: error.rawValue, role: role as? String)
        }.value
        guard !request.onMain, request.code == AXError.success.rawValue,
              request.role == kAXApplicationRole as String else {
            XCTFail("Could not initialize this test process's accessibility tree: onMain=\(request.onMain), code=\(request.code), role=\(String(describing: request.role))", file: file, line: line)
            throw AccessibilityRequestFailure.failed
        }
    }

    static func stringAttribute(_ name: String, of element: NSObject) -> String? {
        let value = attribute(name, of: element)
        if let attributed = value as? NSAttributedString { return attributed.string }
        return value as? String
    }

    static func readableValue(of element: NSObject) -> String? {
        // AppKit exposes a human-readable value separately from the raw value.
        // Prefer the published description when checking what an assistive
        // client reads, without manufacturing an expected value.
        if let description = stringAttribute("accessibilityValueDescription", of: element), !description.isEmpty {
            return description
        }
        return stringAttribute("accessibilityValue", of: element)
    }

    static func elements(in root: NSObject) -> [NSObject] {
        var visited = Set<ObjectIdentifier>()
        var elements: [NSObject] = []
        func visit(_ element: NSObject, depth: Int) {
            guard depth < 128, visited.count < 8_192,
                  visited.insert(ObjectIdentifier(element)).inserted else { return }
            // Keep transient virtual nodes alive for the whole traversal. An
            // address reused after release must not suppress another sibling.
            elements.append(element)
            for child in attribute("accessibilityChildren", of: element) as? [Any] ?? [] {
                if let child = child as? NSObject { visit(child, depth: depth + 1) }
            }
            // Native wrappers and virtual children can coexist; a nonempty AX
            // child list does not mean all native descendants were represented.
            if let view = element as? NSView {
                for child in view.subviews { visit(child, depth: depth + 1) }
            }
        }
        visit(root, depth: 0)
        return elements
    }

    static func renderedText(in root: NSView) -> String {
        elements(in: root).flatMap { element in
            [stringAttribute("accessibilityLabel", of: element),
             stringAttribute("accessibilityValue", of: element)].compactMap { $0 }
        }.joined(separator: "\n")
    }

    private static func attribute(_ name: String, of element: NSObject) -> AnyObject? {
        let selector = NSSelectorFromString(name)
        return element.responds(to: selector) ? element.perform(selector)?.takeUnretainedValue() : nil
    }

    private enum AccessibilityRequestFailure: Error { case failed }
}
#endif
