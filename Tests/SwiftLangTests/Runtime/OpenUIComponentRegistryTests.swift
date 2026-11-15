import XCTest
import SwiftUI
@testable import SwiftLang

final class OpenUIComponentRegistryTests: XCTestCase {
    func testCustomRegistrationAndRemoval() {
        var registry = OpenUIComponentRegistry()
        registry["Example"] = { _, _ in AnyView(EmptyView()) }
        XCTAssertNotNil(registry["Example"])
        registry["Example"] = nil
        XCTAssertNil(registry["Example"])
    }

    func testPresentationMetadataIsRegistryScoped() {
        var first = OpenUIComponentRegistry()
        let second = OpenUIComponentRegistry()
        first["Example"] = { _, _ in AnyView(EmptyView()) }
        first.setPresentationPlaceholder("Example", enabled: true)
        XCTAssertTrue(first.supportsPresentationPlaceholder("Example"))
        XCTAssertFalse(second.supportsPresentationPlaceholder("Example"))
    }
}
