import SwiftLang
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// A native tap inspects a point without capturing a containing scroll view's
/// swipe. Touch-and-hold belongs to the chart's context menu; desktop dragging
/// keeps its existing continuous inspection behavior.
struct NativeChartInteraction: ViewModifier {
    let inspect: (CGPoint?, Bool) -> Void
    #if !os(iOS)
    @GestureState private var dragging = false
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        content.overlay {
            NativeChartTouchInspection(inspect: inspect).accessibilityHidden(true)
        }
        #else
        content.gesture(
            DragGesture(minimumDistance: 0)
                .updating($dragging) { _, active, _ in active = true }
                .onChanged { inspect($0.location, false) }
                .onEnded { _ in inspect(nil, false) }
        )
        .onChange(of: dragging) { active in if !active { inspect(nil, false) } }
        #endif
    }
}

#if os(iOS)
private struct NativeChartTouchInspection: UIViewRepresentable {
    let inspect: (CGPoint?, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(inspect: inspect) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.name = "openui.chart.inspection.tap"
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.inspect = inspect
    }

    final class Coordinator: NSObject {
        var inspect: (CGPoint?, Bool) -> Void
        init(inspect: @escaping (CGPoint?, Bool) -> Void) { self.inspect = inspect }

        @objc func tapped(_ tap: UITapGestureRecognizer) {
            if tap.state == .ended { inspect(tap.location(in: tap.view), true) }
        }
    }
}
#endif
