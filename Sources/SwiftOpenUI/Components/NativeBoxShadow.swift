import SwiftUI

extension View {
    /// Paints an outer box shadow without affecting layout, hit testing, or child content.
    /// The corner radius describes the unexpanded box with native continuous corners.
    public func openUIShadow(_ shadow: OpenUIShadow, cornerRadius: CGFloat = 0) -> some View {
        background { NativeBoxShadow(shadow: shadow, cornerRadius: cornerRadius) }
    }
}

/// Shadows originate from an opaque box even when its actual fill is transparent.
/// Each layer is blurred independently, then the original box is removed from the result.
struct NativeBoxShadow: View {
    let shadow: OpenUIShadow
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let layers = shadow.resolvedLayers(for: colorScheme).filter {
            $0.opacity.isFinite && $0.opacity > 0 && $0.blurRadius.isFinite
                && $0.x.isFinite && $0.y.isFinite && $0.spread.isFinite
                && (max(0, $0.spread) + max(abs($0.x), abs($0.y)) + max(0, $0.blurRadius) * 2).isFinite
        }
        // Four standard deviations retain the visible blur tail. Only the
        // background canvas grows; the decorated view reports its original size.
        let outset = layers.reduce(CGFloat.zero) { result, layer in
            max(result, max(0, layer.spread) + max(abs(layer.x), abs(layer.y))
                + max(0, layer.blurRadius) * 2)
        }.rounded(.up)
        Canvas { context, size in
            let box = CGRect(x: outset, y: outset,
                width: max(0, size.width - 2 * outset), height: max(0, size.height - 2 * outset))
            guard box.width > 0, box.height > 0, !layers.isEmpty else { return }
            let radius = min(cornerRadius.isFinite ? max(0, cornerRadius) : 0,
                min(box.width, box.height) / 2)
            let boxPath = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: box)
            context.drawLayer { shadows in
                for layer in layers.reversed() {
                    let width = box.width + layer.spread * 2
                    let height = box.height + layer.spread * 2
                    guard width.isFinite, height.isFinite, width > 0, height > 0 else { continue }
                    let projected = CGRect(x: box.minX - layer.spread + layer.x,
                        y: box.minY - layer.spread + layer.y, width: width, height: height)
                    // CSS keeps small corners sharp as a positive spread grows.
                    let ratio = layer.spread > radius ? radius / layer.spread - 1 : 0
                    let cornerSpread = layer.spread > radius
                        ? layer.spread * (1 + ratio * ratio * ratio) : layer.spread
                    let projectedRadius = max(0, radius + cornerSpread)
                    let path = RoundedRectangle(cornerRadius: projectedRadius, style: .continuous)
                        .path(in: projected)
                    var single = shadows
                    // Canvas blur takes Gaussian sigma, not the CSS blur radius.
                    single.addFilter(.blur(radius: max(0, layer.blurRadius) / 2))
                    single.fill(path, with: .color(.black.opacity(min(1, layer.opacity))))
                }
                // Isolate the knockout from the host background and remove it
                // after blurring, so transparent card interiors stay transparent.
                shadows.blendMode = .destinationOut
                shadows.fill(boxPath, with: .color(.black))
            }
        }
        .padding(-outset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
