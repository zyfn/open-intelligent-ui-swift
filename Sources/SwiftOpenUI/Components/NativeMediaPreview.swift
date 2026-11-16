import SwiftLang
import Foundation

/// Source-proportional geometry. Unknown or invalid source sizes use a loading
/// placeholder ratio; valid images do not acquire a private aspect-ratio limit.
enum NativeMediaPreview {
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
