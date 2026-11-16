import SwiftLang
import SwiftUI
import XCTest
@testable import SwiftOpenUI

final class ArtworkCardLayoutTests: XCTestCase {
  func testOverflowingCopyMovesBelowTheUnchangedPhotoInsteadOfBeingClipped() {
    for width in [CGFloat(160), 320, 600] {
      let short = NativeArtworkCardMetrics(width: width, aspectRatio: 1.5,
        copyHeight: width / 1.5 / 3, accessibility: false)
      XCTAssertTrue(short.overlaysCopy)
      XCTAssertEqual(short.size.height, width / 1.5, accuracy: 0.01)
      XCTAssertEqual(short.copy.maxY, short.photo.maxY, accuracy: 0.01)
      XCTAssertGreaterThanOrEqual(short.copy.minY, short.photo.midY,
        "Compact copy must leave the upper photograph visible")
      let dense = NativeArtworkCardMetrics(width: width, aspectRatio: 1.5,
        copyHeight: short.photo.height * 0.75, accessibility: false)
      XCTAssertFalse(dense.overlaysCopy,
        "Copy can fit inside the image and still obscure too much of it")
      XCTAssertEqual(dense.copy.minY, dense.photo.maxY, accuracy: 0.01)
      let tall = NativeArtworkCardMetrics(width: width, aspectRatio: 1.5, copyHeight: 700, accessibility: false)
      XCTAssertFalse(tall.overlaysCopy)
      XCTAssertEqual(tall.photo, short.photo)
      XCTAssertEqual(tall.copy.minY, tall.photo.maxY, accuracy: 0.01)
      XCTAssertEqual(tall.copy.height, 700)
      XCTAssertEqual(tall.size.height, tall.copy.maxY, accuracy: 0.01)
    }
  }
  func testAccessibilityReflowsEvenWhenShortCopyCouldFitOnThePhoto() {
    let layout = NativeArtworkCardMetrics(width: 320, aspectRatio: 1.5, copyHeight: 80, accessibility: true)
    XCTAssertFalse(layout.overlaysCopy)
    XCTAssertEqual(layout.photo.height, 320 / 1.5, accuracy: 0.01)
    XCTAssertEqual(layout.copy.minY, layout.photo.maxY, accuracy: 0.01)
    XCTAssertEqual(layout.copy.height, 80)
  }
}
