import SwiftLang
#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import SwiftOpenUI

final class NativeActionAccessoryTests: XCTestCase {
    @MainActor func testProgressKeepsConversationTextAndMeasuredSizeInBothDirections() throws {
        _ = NSApplication.shared
        for placement in [NativeConversationActionLabel.Placement.centered, .suggestion] {
            for type in [DynamicTypeSize.large, .accessibility2] {
                for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                    let progress = ActionAccessoryProgress()
                    let host = NSHostingView(rootView: ActionAccessoryFixture(progress: progress,
                        placement: placement, type: type, direction: direction))
                    let size = host.fittingSize
                    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                        styleMask: [.borderless], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.contentView = host
                    window.setFrameOrigin(.init(x: -10000, y: -10000))
                    window.orderFront(nil)
                    defer { window.close() }
                    settle(host)
                    let initialSize = host.fittingSize
                    let initialInk = try middleTextInk(host)
                    XCTAssertGreaterThan(initialInk, 50, "A blank label is not a passing visibility test")

                    progress.active = true
                    settle(host)
                    let workingSize = host.fittingSize
                    let workingInk = try middleTextInk(host)
                    XCTAssertEqual(workingSize.width, initialSize.width, accuracy: 1)
                    XCTAssertEqual(workingSize.height, initialSize.height, accuracy: 1)
                    XCTAssertGreaterThanOrEqual(Double(workingInk), Double(initialInk) * 0.95,
                        "The progress accessory must not hide or dim the complete question/action text")

                    progress.active = false
                    settle(host)
                    XCTAssertEqual(host.fittingSize.height, initialSize.height, accuracy: 1)
                }
            }
        }
    }

    @MainActor private func settle<V: View>(_ host: NSHostingView<V>) {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        host.layoutSubtreeIfNeeded()
    }

    /// Ignore both accessory edges, so a changing arrow/spinner cannot make
    /// disappearing text pass merely because some new pixels were painted.
    @MainActor private func middleTextInk<V: View>(_ host: NSHostingView<V>) throws -> Int {
        let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: image)
        var count = 0
        let lower = Int(Double(image.pixelsWide) * 0.2)
        let upper = Int(Double(image.pixelsWide) * 0.7)
        for y in 0..<image.pixelsHigh {
            for x in lower..<upper {
                if let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   color.alphaComponent > 0.5,
                   color.redComponent + color.greenComponent + color.blueComponent < 1.2 {
                    count += 1
                }
            }
        }
        return count
    }
}

@MainActor private final class ActionAccessoryProgress: ObservableObject {
    @Published var active = false
}

private struct ActionAccessoryFixture: View {
    @ObservedObject var progress: ActionAccessoryProgress
    let placement: NativeConversationActionLabel.Placement
    let type: DynamicTypeSize
    let direction: LayoutDirection
    private var presentation: OpenUIPresentation {
        var value = OpenUIPresentation()
        value.motion.loadingIndicatorDelay = 0
        return value
    }
    var body: some View {
        NativeConversationActionLabel(text: "如何保留完整问题并根据当前选择继续安排下一步？",
            theme: .defaults, placement: placement, fillsWidth: true)
            .nativeTextStyle(OpenUIThemeValues.defaults.textStyle(.action))
            .modifier(NativeActionProgress(active: progress.active, usesAccessory: true))
            .environment(\.openUIActionAppearance, progress.active ? .performing : .ready)
            .environment(\.isEnabled, !progress.active)
            .environment(\.layoutDirection, direction)
            .environment(\.colorScheme, .light)
            .environment(\.openUIPresentation, presentation)
            .dynamicTypeSize(type)
            .frame(width: 280)
            .background(Color.white)
    }
}
#endif
