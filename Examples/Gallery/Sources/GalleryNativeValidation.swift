#if DEBUG && os(iOS)
import SwiftUI

/// Fixed integration scenes used by the Gallery UI Testing Bundle. The normal
/// Gallery route is unchanged; XCTest explicitly selects a scene at launch.
@MainActor struct GalleryNativeValidationView: View {
    let scenario: String
    private let environment = ProcessInfo.processInfo.environment

    private var width: CGFloat {
        guard let raw = environment["OPENUI_UI_TEST_WIDTH"], let value = Double(raw),
              value.isFinite, (240...600).contains(value) else { return 320 }
        return CGFloat(value)
    }

    private var typeSize: DynamicTypeSize {
        environment["OPENUI_UI_TEST_SIZE"] == "accessibility2" ? .accessibility2 : .large
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Native validation: \(scenario)")
                    .font(.caption2)
                    .accessibilityIdentifier("validation.ready")
                scene
            }
            .frame(width: width, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, typeSize)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .background(Color.white)
    }

    @ViewBuilder private var scene: some View {
        if scenario.hasPrefix("product-") {
            GalleryProductValidationView(scenario: scenario)
        } else if scenario.hasPrefix("controls-") {
            GalleryControlValidationView(scenario: scenario)
        } else if scenario.hasPrefix("layout-") {
            GalleryLayoutValidationView(scenario: scenario)
        } else {
            Text("Unknown native validation scene: \(scenario)")
                .accessibilityIdentifier("validation.failure")
        }
    }
}
#endif
