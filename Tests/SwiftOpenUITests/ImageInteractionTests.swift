import SwiftLang
import Foundation
import SwiftUI
import XCTest
@testable import SwiftOpenUI

final class ImageInteractionTests: XCTestCase {
  func testPreviewPixelRequestsUseTheEffectiveHostLimit() {
    let limits = OpenUIResourceLimits(maximumImagePixelSize: 1024)
    let viewport = CGSize(width: 800, height: 600)
    XCTAssertEqual(NativeMediaPreview.pixelSize(viewport: viewport, scale: 2, limits: limits), 1024)
    XCTAssertEqual(NativeMediaPreview.pixelSize(viewport: viewport, scale: 2, zoom: 5, limits: limits), 1024)
    XCTAssertEqual(NativeMediaPreview.pixelSize(viewport: CGSize(width: 100, height: 100),
      scale: 2, limits: limits), 256)
  }

  func testMediaPageWindowIsBoundedAtEdgesAndAfterLargeJumps() {
    for count in [0, 1, 2, 40, 10_000] {
      for selected in [-1, 0, 1, count / 2, max(0, count - 1), count] {
        let window = NativePagerWindow.range(count: count, selected: selected, radius: 1)
        XCTAssertLessThanOrEqual(window.count, 3)
        XCTAssertGreaterThanOrEqual(window.lowerBound, 0)
        XCTAssertLessThanOrEqual(window.upperBound, count)
        if count > 0 { XCTAssertTrue(window.contains(min(count - 1, max(0, selected)))) }
      }
    }
    XCTAssertEqual(NativePagerWindow.range(count: 40, selected: 20, radius: nil), 0..<40,
      "Existing stateful card pagers keep their mounted presentation by default")
  }

  func testChangingThePreviewImageResetsZoomAndPan() {
    let size = CGSize(width: 320, height: 500)
    var state = NativeImageZoomState()
    state.setScale(2, size: size)
    state.offset = state.bounded(CGSize(width: 800, height: -800), scale: state.scale, size: size)
    XCTAssertTrue(state.isZoomed)
    XCTAssertEqual(state.offset, CGSize(width: 160, height: -250))
    state.reset()
    XCTAssertFalse(state.isZoomed)
    XCTAssertEqual(state.offset, .zero)
    state.setScale(100, size: size)
    XCTAssertEqual(state.scale, 5)
    state.setScale(0, size: size)
    XCTAssertEqual(state.scale, 1)
    XCTAssertEqual(state.offset, .zero)
  }

  func testPreviewChromeUsesTheScopedEnglishOrChineseLocale() {
    let chinese = Locale(identifier: "zh-Hans"), english = Locale(identifier: "en_US")
    XCTAssertEqual(NativeControlText.localized("Image preview", locale: chinese), "图片预览")
    XCTAssertEqual(NativeControlText.localized("Image preview", locale: english), "Image preview")
    XCTAssertEqual(NativeControlText.localized("Swipe to change image", locale: chinese), "左右滑动切换图片")
    XCTAssertEqual(NativeControlText.localized("Swipe to change image", locale: english), "Swipe left or right to change image")
    XCTAssertEqual(NativeControlText.localized("Drag to move image", locale: chinese), "拖动查看放大的图片")
    XCTAssertEqual(NativeControlText.localized("Close image preview", locale: chinese), "关闭图片预览")
    XCTAssertEqual(NativeControlText.localized("Close image preview", locale: english), "Close image preview")
    XCTAssertEqual(NativeControlText.localized("A user supplied caption", locale: chinese), "A user supplied caption")
  }

  func testBundledEnglishAndChineseControlKeysStayPaired() throws {
    func keys(_ language: String) throws -> Set<String> {
      let resolved = try XCTUnwrap(Bundle.preferredLocalizations(
        from: NativeControlResources.bundle.localizations, forPreferences: [language]).first)
      let folder = try XCTUnwrap(NativeControlResources.bundle.path(forResource: resolved, ofType: "lproj"))
      let data = try Data(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent("Localizable.strings"))
      let values = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
      return Set(values.keys)
    }
    XCTAssertEqual(try keys("en"), try keys("zh-Hans"))
  }

  func testRetryAttemptsBelongToTheExactSourceAndResourceOwner() {
    let a = OpenUIURLSessionResourceLoader(), b = OpenUIURLSessionResourceLoader()
    let url = URL(string: "https://example.com/image.png?signature=a%26b")!
    let first = NativeResourceRequestID(request: URLRequest(url: url), loader: ObjectIdentifier(a), attempt: 0)
    let otherOwner = NativeResourceRequestID(request: URLRequest(url: url), loader: ObjectIdentifier(b), attempt: 0)
    var retry = NativeImageRetryState()
    retry.retry(first); retry.retry(first)
    XCTAssertEqual(retry.attempt(for: first), 2)
    XCTAssertEqual(retry.attempt(for: otherOwner), 0)
    retry.retry(otherOwner)
    XCTAssertEqual(retry.attempt(for: otherOwner), 1)
    XCTAssertEqual(retry.attempt(for: first), 0)
  }
}
