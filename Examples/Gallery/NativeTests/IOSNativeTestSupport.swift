#if os(iOS)
import SwiftUI
import UIKit
import XCTest

/// Real UIKit hosting inside the Gallery application's unit-test bundle.
/// Each test owns a window in the running app's scene and restores the previous
/// key window when finished; UIKit control events use the real application.
@MainActor final class IOSNativeTestHost {
    let window: UIWindow
    let controller: UIHostingController<AnyView>
    private weak var previousKeyWindow: UIWindow?

    init<Content: View>(_ content: Content, width: CGFloat = 390, height: CGFloat = 1400) throws {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = try XCTUnwrap(scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
                                 "Mounted native tests require the Gallery app's UIWindowScene")
        previousKeyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
        controller = UIHostingController(rootView: AnyView(content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()))
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        window = UIWindow(windowScene: scene)
        window.frame = bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        layout()
    }

    func layout() {
        window.layoutIfNeeded()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    }

    func close() {
        window.endEditing(true)
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
    }

    func waitUntil(_ message: String, timeout: TimeInterval = 5,
        file: StaticString = #filePath, line: UInt = #line,
        _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            layout()
            if condition() {
                await Task.yield()
                layout()
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        } while Date() < deadline
        let label = String(message.map { $0.isLetter || $0.isNumber ? $0 : "-" }.prefix(80))
        try? saveSnapshot(name: "timeout-" + label)
        XCTFail("Timed out: \(message). Rendered text: \(renderedText())", file: file, line: line)
        throw ObservationFailure.timeout
    }

    func descendants<T: UIView>(of type: T.Type) -> [T] {
        func visit(_ view: UIView) -> [T] {
            ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap(visit)
        }
        return visit(window)
    }

    func renderedText() -> String {
        // In-process XCTest can inspect concrete UIKit views. SwiftUI's
        // virtual accessibility tree is read by the Gallery XCUITest target.
        (descendants(of: UILabel.self).compactMap(\.text)
            + descendants(of: UITextField.self).compactMap(\.text)
            + descendants(of: UITextView.self).compactMap(\.text)).joined(separator: "\n")
    }

    func snapshot(view: UIView? = nil) -> UIImage {
        layout()
        let capturedView = view ?? controller.view!
        capturedView.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(bounds: capturedView.bounds, format: format).image { context in
            UIColor.white.setFill()
            context.fill(capturedView.bounds)
            // A software capture includes the complete test window, including
            // content outside the physical phone viewport used for width cases.
            capturedView.layer.render(in: context.cgContext)
        }
    }

    func saveSnapshot(name: String, view: UIView? = nil) throws {
        guard let output = ProcessInfo.processInfo.environment["OPENUI_SNAPSHOT_DIR"], !output.isEmpty else { return }
        let directory = URL(fileURLWithPath: output).appendingPathComponent("ios-native", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(snapshot(view: view).pngData()).write(to: directory.appendingPathComponent(name + ".png"))
    }

    private enum ObservationFailure: Error { case timeout }
}
#endif
