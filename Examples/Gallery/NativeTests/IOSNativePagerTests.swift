#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import SwiftOpenUI

final class IOSNativePagerTests: XCTestCase {
    @available(iOS 18, *)
    @MainActor private func assertHorizontalDelegateAcceptsOnlyPredominantlyHorizontalMovement() {
        // This checks the production delegate's direction rule. Real touch
        // delivery and competition with vertical scrolling belong to XCUITest.
        let delegate = NativeHorizontalPanGesture.Coordinator()
        let input = IOSVelocityPan()
        for (velocity, expected) in [
            (CGPoint(x: 500, y: 20), true),
            (CGPoint(x: -500, y: 20), true),
            (CGPoint(x: 20, y: 500), false),
            (CGPoint(x: 20, y: -500), false),
            (CGPoint.zero, false),
        ] {
            input.testVelocity = velocity
            XCTAssertEqual(delegate.gestureRecognizerShouldBegin(input), expected,
                "The horizontal pager must leave predominantly vertical gestures to the surrounding page")
        }
    }

    @MainActor func testMountedPagerKeepsPagesAcrossEnabledAndSelectionUpdates() async throws {
        if #available(iOS 18, *) {
            assertHorizontalDelegateAcceptsOnlyPredominantlyHorizontalMovement()
        }
        let state = IOSPagerInteractionState()
        let host = try IOSNativeTestHost(IOSPagerInteractionFixture(state: state), width: 320, height: 240)
        defer { host.close() }
        try await host.waitUntil("all real pager pages have received their initial configuration") {
            state.views.count == 3 && state.mounted.count == 3
                && state.mounted.values.allSatisfy { $0 == state.configuration }
        }
        let original = state.views
        try assertMountedPages(state, original: original, in: host)

        for (enabled, selected) in [(false, 0), (false, 1), (true, 1), (true, 2)] {
            state.enabled = enabled
            state.selected = selected
            // Synchronize with native updateUIView delivery, not the expected
            // geometry or identity that the assertions below must verify.
            try await host.waitUntil("the same pager pages receive enabled=\(enabled), selected=\(selected)") {
                state.mounted.count == 3 && state.mounted.values.allSatisfy { $0 == state.configuration }
            }
            try assertMountedPages(state, original: original, in: host)
        }
        XCTAssertTrue(state.selectionWrites.isEmpty,
            "Mounting, changing interactivity and applying an external selection must not emit a user selection")
    }

    @MainActor private func assertMountedPages(_ state: IOSPagerInteractionState,
        original: [Int: UIView], in host: IOSNativeTestHost,
        file: StaticString = #filePath, line: UInt = #line) throws {
        for id in 0..<3 {
            let view = try XCTUnwrap(state.views[id], file: file, line: line)
            XCTAssertTrue(view === original[id], "The actual page must keep its native identity", file: file, line: line)
            XCTAssertTrue(view.window === host.window, file: file, line: line)
            XCTAssertEqual(state.created[id], 1, file: file, line: line)
            XCTAssertEqual(state.removed[id, default: 0], 0, file: file, line: line)
            let frame = view.convert(view.bounds, to: host.controller.view)
            XCTAssertEqual(frame.width, 320, accuracy: 1, file: file, line: line)
            XCTAssertEqual(frame.height, 100, accuracy: 1, file: file, line: line)
            XCTAssertEqual(frame.minX, CGFloat(id - state.selected) * 320, accuracy: 1,
                "Selection moves the mounted track while retaining every page", file: file, line: line)
        }
        XCTAssertTrue(state.selectionWrites.isEmpty,
            "An update must not manufacture a pager selection callback", file: file, line: line)
    }
}

private struct IOSPagerConfiguration: Equatable {
    let enabled: Bool
    let selected: Int
}

@MainActor private final class IOSPagerInteractionState: ObservableObject {
    @Published var enabled = true
    @Published var selected = 0
    var views: [Int: UIView] = [:]
    var mounted: [Int: IOSPagerConfiguration] = [:]
    var created: [Int: Int] = [:]
    var removed: [Int: Int] = [:]
    var selectionWrites: [Int] = []

    var configuration: IOSPagerConfiguration { .init(enabled: enabled, selected: selected) }
    var selection: Binding<Int> {
        Binding(get: { self.selected }, set: {
            self.selectionWrites.append($0)
            self.selected = $0
        })
    }
}

private struct IOSPagerInteractionFixture: View {
    @ObservedObject var state: IOSPagerInteractionState
    var body: some View {
        NativePager(ids: [0, 1, 2], selection: state.selection, enabled: state.enabled,
            identifier: "validation.pager") { id in
            Text("Pager page \(id + 1)")
                .frame(maxWidth: .infinity).frame(height: 100)
                .background(IOSPagerIdentityMarker(id: id, state: state, configuration: state.configuration))
        }
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }
}

private struct IOSPagerIdentityMarker: UIViewRepresentable {
    let id: Int
    let state: IOSPagerInteractionState
    let configuration: IOSPagerConfiguration

    func makeCoordinator() -> (Int, IOSPagerInteractionState) { (id, state) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        state.views[id] = view
        state.created[id, default: 0] += 1
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { state.mounted[id] = configuration }
    static func dismantleUIView(_ view: UIView, coordinator: (Int, IOSPagerInteractionState)) {
        coordinator.1.removed[coordinator.0, default: 0] += 1
    }
}

@MainActor private final class IOSVelocityPan: UIPanGestureRecognizer {
    var testVelocity = CGPoint.zero
    override func velocity(in view: UIView?) -> CGPoint { testVelocity }
}
#endif
