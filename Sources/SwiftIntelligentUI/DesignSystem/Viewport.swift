import SwiftUI

extension EnvironmentValues {
    /// The enclosing visible container, independent of a message's content height.
    /// Percent lengths continue to use the immediate layout proposal instead.
    @Entry var openIntelligentUIViewportSize: CGSize? = nil
}

enum IntelligentUIViewportGeometry {
    static func valid(_ size: CGSize) -> CGSize? {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return nil }
        return size
    }
}

/// Captures geometry at the renderer boundary, not once per Box. A background
/// probe does not turn content-sized messages into full-height containers.
struct IntelligentUIViewportModifier: ViewModifier {
    @State private var viewport: CGSize?

    func body(content: Content) -> some View {
        content
            .environment(\.openIntelligentUIViewportSize, viewport)
            .background(alignment: .topLeading) {
                probe.allowsHitTesting(false).accessibilityHidden(true)
            }
    }

    @ViewBuilder private var probe: some View {
        if #available(iOS 17, macOS 14, *) {
            Color.clear
                .containerRelativeFrame([.horizontal, .vertical], alignment: .topLeading)
                .onGeometryChange(for: CGSize?.self) { geometry in
                    IntelligentUIViewportGeometry.valid(geometry.size)
                } action: { size in
                    if viewport != size { viewport = size }
                }
        } else {
            NativeIntelligentUIViewportProbe { size in
                if viewport != size { viewport = size }
            }
        }
    }
}

// The deployment targets predate containerRelativeFrame. These probes only
// read their own enclosing scroll view/window, never a process-global screen.
// Notifications are delivered outside layout; no document state is mutated.
#if canImport(UIKit)
import UIKit

private struct NativeIntelligentUIViewportProbe: UIViewRepresentable {
    let onChange: (CGSize?) -> Void

    func makeUIView(context: Context) -> ViewportView {
        let view = ViewportView()
        view.isUserInteractionEnabled = false
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: ViewportView, context: Context) {
        view.onChange = onChange
        view.refreshContainer()
    }

    static func dismantleUIView(_ view: ViewportView, coordinator: Void) {
        view.invalidate()
    }

    final class ViewportView: UIView {
        var onChange: ((CGSize?) -> Void)?
        private weak var container: UIView?
        private var observations: [NSKeyValueObservation] = []
        private var isActive = true
        private var pending = false
        private var measured: CGSize?

        override func didMoveToWindow() { super.didMoveToWindow(); refreshContainer() }
        override func didMoveToSuperview() { super.didMoveToSuperview(); refreshContainer() }
        override func layoutSubviews() { super.layoutSubviews(); refreshContainer() }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); measure() }

        func refreshContainer() {
            guard isActive else { return }
            var ancestor = superview
            var next: UIView?
            while let view = ancestor {
                if view is UIScrollView { next = view; break }
                ancestor = view.superview
            }
            if next == nil { next = window }
            if next !== container {
                observations.forEach { $0.invalidate() }
                observations.removeAll()
                container = next
                if let next {
                    observations.append(next.observe(\.bounds, options: [.new]) { [weak self] _, _ in
                        DispatchQueue.main.async { [weak self] in self?.measure() }
                    })
                }
                if let scroll = next as? UIScrollView {
                    // Insets can change without resizing bounds, for example
                    // when a host reserves space for its input controls.
                    observations.append(scroll.observe(\.contentInset, options: [.new]) { [weak self] _, _ in
                        DispatchQueue.main.async { [weak self] in self?.measure() }
                    })
                    observations.append(scroll.observe(\.adjustedContentInset, options: [.new]) { [weak self] _, _ in
                        DispatchQueue.main.async { [weak self] in self?.measure() }
                    })
                }
            }
            measure()
        }

        func invalidate() {
            isActive = false
            onChange = nil
            observations.forEach { $0.invalidate() }
            observations.removeAll()
            container = nil
            measured = nil
            pending = false
        }

        private func measure() {
            guard isActive else { return }
            let size: CGSize?
            if let scroll = container as? UIScrollView {
                size = IntelligentUIViewportGeometry.valid(scroll.bounds.inset(by: scroll.adjustedContentInset).size)
            } else {
                size = container.flatMap { IntelligentUIViewportGeometry.valid($0.safeAreaLayoutGuide.layoutFrame.size) }
            }
            guard size != measured else { return }
            measured = size
            guard !pending else { return }
            pending = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isActive else { return }
                self.pending = false
                self.onChange?(self.measured)
            }
        }
    }
}
#elseif canImport(AppKit)
import AppKit

private struct NativeIntelligentUIViewportProbe: NSViewRepresentable {
    let onChange: (CGSize?) -> Void

    func makeNSView(context: Context) -> ViewportView {
        let view = ViewportView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ViewportView, context: Context) {
        view.onChange = onChange
        view.refreshContainer()
    }

    static func dismantleNSView(_ view: ViewportView, coordinator: Void) {
        view.invalidate()
    }

    final class ViewportView: NSView {
        var onChange: ((CGSize?) -> Void)?
        private weak var container: NSView?
        private var observations: [NSObjectProtocol] = []
        private var isActive = true
        private var pending = false
        private var measured: CGSize?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshContainer() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); refreshContainer() }
        override func layout() { super.layout(); refreshContainer() }

        func refreshContainer() {
            guard isActive else { return }
            let next: NSView? = enclosingScrollView?.contentView ?? window?.contentView
            if next !== container {
                observations.forEach { NotificationCenter.default.removeObserver($0) }
                observations.removeAll()
                container = next
                if let next {
                    next.postsFrameChangedNotifications = true
                    next.postsBoundsChangedNotifications = true
                    for name in [NSView.frameDidChangeNotification, NSView.boundsDidChangeNotification] {
                        observations.append(NotificationCenter.default.addObserver(forName: name, object: next, queue: .main) { [weak self] _ in
                            DispatchQueue.main.async { [weak self] in self?.measure() }
                        })
                    }
                }
            }
            measure()
        }

        func invalidate() {
            isActive = false
            onChange = nil
            observations.forEach { NotificationCenter.default.removeObserver($0) }
            observations.removeAll()
            container = nil
            measured = nil
            pending = false
        }

        private func measure() {
            guard isActive else { return }
            let size = container.flatMap { view in
                IntelligentUIViewportGeometry.valid(view is NSClipView ? view.bounds.size : view.safeAreaRect.size)
            }
            guard size != measured else { return }
            measured = size
            guard !pending else { return }
            pending = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isActive else { return }
                self.pending = false
                self.onChange?(self.measured)
            }
        }

        deinit { observations.forEach { NotificationCenter.default.removeObserver($0) } }
    }
}
#endif
