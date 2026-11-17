import SwiftLang
import Foundation

/// Source-proportional geometry. Unknown or invalid source sizes use a loading
/// placeholder ratio; valid images do not acquire a private aspect-ratio limit.
enum NativeMediaPreview {
  static func displaySize(viewport: CGSize, scale: CGFloat,
                          mode: NativeImageDisplaySize.Mode) -> NativeImageDisplaySize? {
    guard scale.isFinite else { return nil }
    let scale = max(1, scale)
    let width = viewport.width * scale
    let height = mode == .width ? 1 : viewport.height * scale
    guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
    // A few layout points must not cancel and restart the same image work.
    // No decoded edge can exceed 2816; larger viewport requirements therefore
    // have the same result under the existing image cap.
    func pixels(_ value: CGFloat) -> Int { max(1, Int(min(2816, ceil(value / 16) * 16))) }
    return NativeImageDisplaySize(width: pixels(width), height: pixels(height), mode: mode)
  }

  static func pixelSize(viewport: CGSize, scale: CGFloat, zoom: CGFloat = 1,
                        limits: OpenUIResourceLimits) -> Int {
    let cap = NativeMediaCache.effectivePixelSize(nil, limits: limits)
    let pixels = max(viewport.width, viewport.height) * max(1, scale) * max(1, zoom)
    guard pixels.isFinite, pixels > 0 else { return cap }
    let tier = [256, 512, 1024, 1600, 2048, 2816].first { CGFloat($0) >= pixels } ?? cap
    return NativeMediaCache.effectivePixelSize(tier, limits: limits)
  }
  static func aspectRatio(sourceSize: CGSize?) -> CGFloat {
    guard let size = sourceSize, size.width.isFinite, size.height.isFinite,
      size.width > 0, size.height > 0 else { return 4 / 3 }
    let ratio = size.width / size.height
    guard ratio.isFinite, ratio > 0 else { return 4 / 3 }
    return ratio
  }
}
