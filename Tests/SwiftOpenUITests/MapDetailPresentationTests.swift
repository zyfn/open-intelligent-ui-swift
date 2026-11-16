import SwiftLang
#if os(macOS)
import AppKit
import MapKit
import SwiftUI
import XCTest
@testable import SwiftOpenUI

final class MapDetailPresentationTests: XCTestCase {
  @MainActor func testPlaceWithoutExternalURLStillHasDetailControlInTheReservedSlot() {
    _ = NSApplication.shared
    let place = NativeMapPlace(id: "place", title: "完整地点名称", image: nil, url: nil,
      description: "地点详情不依赖外部网页。", coordinate: .init(latitude: 31.2, longitude: 121.5))
    let host = NSHostingView(rootView: NativeMapPlaceDetailsButton(place: place, enabled: true, select: {}))
    XCTAssertEqual(host.fittingSize.width, 44, accuracy: 1)
    XCTAssertEqual(host.fittingSize.height, 44, accuracy: 1)
  }

  @MainActor func testLongChineseDetailsGrowBeyondTheCompactCardAtNarrowWidthsAndLargeType() {
    _ = NSApplication.shared
    func height(_ description: String, width: CGFloat, type: DynamicTypeSize) -> CGFloat {
      let place = NativeMapPlace(id: "place", title: "完整地点名称，包含必要的分馆与入口说明", image: nil, url: nil,
        description: description, coordinate: .init(latitude: 31.2, longitude: 121.5))
      return NSHostingView(rootView: NativeMapPlaceDetailContent(place: place)
        .dynamicTypeSize(type).frame(width: width)).fittingSize.height
    }
    for width: CGFloat in [220, 320] {
      for type in [DynamicTypeSize.large, .accessibility3] {
        let short = height("从北门进入。", width: width, type: type)
        let full = height(String(repeating: "从北门进入后沿无障碍通道前行，穿过大厅即可到达参观入口。", count: 16),
          width: width, type: type)
        XCTAssertGreaterThan(full, short + 200,
          "The actual detail content must lay out complete copy instead of inheriting the map card's line limits")
      }
    }
  }
}
#endif
