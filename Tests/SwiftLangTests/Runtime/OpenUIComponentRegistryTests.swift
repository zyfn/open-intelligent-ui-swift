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

    func testTypedPresentationValuesFollowTheRegisteredRenderer() throws {
        let original = OpenUIComponent(name: "Example", description: "Native metadata probe",
            params: [OpenUIParameter.string("mode")]) { _ in EmptyView() }
            .presentation(RegistryPresentationProbeKey.self, value: 160)
            .presentation(layoutFields: ["mode"])
        let library = try OpenUIComponentLibrary(components: [original])
        XCTAssertEqual(library.registry.presentationValue("Example", RegistryPresentationProbeKey.self), 160)

        let renamed = original.replacingDefinition(defineComponent(name: "Renamed", description: "Same renderer",
            params: []))
        let extended = try library.extending(adding: [renamed])
        XCTAssertEqual(extended.registry.presentationValue("Renamed", RegistryPresentationProbeKey.self), 160)
        XCTAssertTrue(extended.registry.presentationLayoutFields("Renamed").isEmpty,
            "Native values survive definition replacement while undeclared Lang fields are filtered")
        XCTAssertNil(library.registry.presentationValue("Renamed", RegistryPresentationProbeKey.self))

        let replacement = OpenUIComponent(original.definition) { _ in Text("Replacement") }
        let overridden = try extended.extending(overriding: [replacement], removing: ["Renamed"])
        XCTAssertNil(overridden.registry.presentationValue("Example", RegistryPresentationProbeKey.self),
            "A new renderer must not inherit the previous renderer's layout policy")
        XCTAssertNil(overridden.registry.presentationValue("Renamed", RegistryPresentationProbeKey.self))
        XCTAssertEqual(extended.registry.presentationValue("Example", RegistryPresentationProbeKey.self), 160,
            "Extending a library must not mutate its original registration values")
    }

    func testChangingTypedPresentationValuesInvalidatesOnlyTheRegistryCopy() {
        var registry = OpenUIComponentRegistry()
        registry["Example"] = { _, _ in AnyView(EmptyView()) }
        let original = registry
        var values = OpenUIContextValues()
        values[RegistryPresentationProbeKey.self] = 240
        registry.setPresentationValues("Example", values: values)
        XCTAssertNotEqual(registry.renderRevision, original.renderRevision)
        XCTAssertNil(original.presentationValue("Example", RegistryPresentationProbeKey.self))
        XCTAssertEqual(registry.presentationValue("Example", RegistryPresentationProbeKey.self), 240)
        registry["Example"] = original["Example"]
        XCTAssertNil(registry.presentationValue("Example", RegistryPresentationProbeKey.self),
            "Direct renderer replacement clears its native metadata even with the same builder")
    }
}

private enum RegistryPresentationProbeKey: OpenUIContextKey {
    static let defaultValue: Int? = nil
}
