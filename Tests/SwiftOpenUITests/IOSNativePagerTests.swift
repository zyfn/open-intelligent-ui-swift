#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import SwiftOpenUI

final class IOSNativePagerTests: XCTestCase {
    @MainActor func testMountedPagerUpdatesItsNativeRecognizerWithoutReplacingIt() async throws {
        let state = IOSPagerInteractionState()
        let host = IOSNativeTestHost(IOSPagerInteractionFixture(state: state), width: 320, height: 240)
        defer { host.close() }
        try await host.waitUntil("the pager's enabled content is mounted") {
            host.renderedText().contains("Pager enabled")
        }
        if #available(iOS 18, *) {
            try await host.waitUntil("the iOS horizontal recognizer is installed") {
                self.pans(in: host).contains { $0.delegate is NativeHorizontalPanGesture.Coordinator }
            }
            let pan = try XCTUnwrap(pans(in: host).first { $0.delegate is NativeHorizontalPanGesture.Coordinator })
            XCTAssertTrue(pan.isEnabled)
            XCTAssertEqual(pan.maximumNumberOfTouches, 1)
            state.enabled = false
            try await host.waitUntil("the disabled environment reaches the mounted pager") {
                host.renderedText().contains("Pager disabled") && !pan.isEnabled
            }
            XCTAssertTrue(pans(in: host).contains { $0 === pan },
                "Changing interactivity updates the recognizer already attached to the native view")
            state.enabled = true
            try await host.waitUntil("the existing native recognizer is enabled again") {
                host.renderedText().contains("Pager enabled") && pan.isEnabled
            }
            XCTAssertTrue(pans(in: host).contains { $0 === pan })

            // The mounted delegate must leave a predominantly vertical gesture
            // to the surrounding page. UIKit supplies velocity; a test subclass
            // supplies only that input, without private touch/event synthesis.
            let delegate = try XCTUnwrap(pan.delegate)
            let input = IOSVelocityPan()
            for (velocity, expected) in [
                (CGPoint(x: 500, y: 20), true),
                (CGPoint(x: -500, y: 20), true),
                (CGPoint(x: 20, y: 500), false),
                (CGPoint(x: 20, y: -500), false),
                (CGPoint.zero, false),
            ] {
                input.testVelocity = velocity
                XCTAssertEqual(delegate.gestureRecognizerShouldBegin?(input), expected,
                    "The horizontal pager must not capture the page's vertical scroll")
            }
        } else {
            // Earlier supported systems use the SwiftUI DragGesture path. This
            // test observes its mounted content; it does not claim a touch trace.
            state.enabled = false
            try await host.waitUntil("the older-system fallback receives disabled content") {
                host.renderedText().contains("Pager disabled")
            }
        }
        XCTAssertEqual(state.changedCount, 0,
            "Installing or enabling a recognizer must not dispatch a user gesture")
        XCTAssertEqual(state.endedCount, 0)
    }

    @MainActor private func pans(in host: IOSNativeTestHost) -> [UIPanGestureRecognizer] {
        host.descendants(of: UIView.self).flatMap { $0.gestureRecognizers ?? [] }
            .compactMap { $0 as? UIPanGestureRecognizer }
    }
}

@MainActor private final class IOSPagerInteractionState: ObservableObject {
    @Published var enabled = true
    var changedCount = 0
    var endedCount = 0
}

private struct IOSPagerInteractionFixture: View {
    @ObservedObject var state: IOSPagerInteractionState
    var body: some View {
        Text(state.enabled ? "Pager enabled" : "Pager disabled")
            .frame(width: 300, height: 100).contentShape(Rectangle())
            .modifier(NativePagerPan(enabled: state.enabled,
                fallback: DragGesture().onChanged { _ in state.changedCount += 1 }
                    .onEnded { _ in state.endedCount += 1 },
                changed: { _ in state.changedCount += 1 }, ended: { _ in state.endedCount += 1 }))
    }
}

@MainActor private final class IOSVelocityPan: UIPanGestureRecognizer {
    var testVelocity = CGPoint.zero
    override func velocity(in view: UIView?) -> CGPoint { testVelocity }
}
#endif
