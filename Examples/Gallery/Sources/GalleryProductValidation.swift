#if DEBUG && os(iOS)
import CoreGraphics
import SwiftUI
import SwiftLang
import SwiftIntelligentUI

/// Fixed UI-validation programs, rendered through the same public SDK entry as
/// ordinary Gallery documents. The validation launch route owns the viewport.
@MainActor struct GalleryProductValidationView: View {
    @StateObject private var model: GalleryProductValidationModel

    init(scenario: String) {
        _model = StateObject(wrappedValue: GalleryProductValidationModel(scenario: scenario))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OpenUIView(state: model.state, library: model.library)
                .openIntelligentUIImages(model.images)
            GalleryProductValidationReceipt(model: model, state: model.state)
        }
    }
}

@MainActor private final class GalleryProductValidationModel: ObservableObject {
    let library: OpenUILibrary
    let state: OpenUIState
    let images: [String: Image]
    let showsAlbumControls: Bool
    let initialContractIssues: [String]
    @Published private(set) var actions: [ActionEvent] = []

    init(scenario: String) {
        let library: OpenUILibrary
        do { library = try OpenUILibrary.openIntelligentUI() }
        catch { preconditionFailure("Cannot create ProductCard validation library: \(error)") }
        let state = library.makeState()
        let source = Self.source(scenario: scenario)
        state.setSource(source)
        let issues: [String]
        do { issues = try OpenIntelligentUIComponents().validationIssues(in: state, source: source) }
        catch { preconditionFailure("Cannot validate ProductCard program: \(error)") }
        self.library = library
        self.state = state
        images = ["marker-red": Self.marker(red: 1, blue: 0), "marker-blue": Self.marker(red: 0, blue: 1)]
        showsAlbumControls = scenario == "product-album"
        initialContractIssues = issues
        state.onAction = { [weak self] event in self?.actions.append(event) }
    }

    func updateTitle() {
        state.setState("$title", value: .string("Updated camera"))
    }

    var lastURL: String {
        guard case .string(let value) = actions.last?.params.first(where: { $0.0 == "url" })?.1 else { return "none" }
        return value.displayString
    }

    private static func source(scenario: String) -> String {
        switch scenario {
        case "product-vertical", "product-horizontal", "product-compact":
            let layout = String(scenario.dropFirst("product-".count))
            return """
            root = Col([ProductCard({id:"camera",title:"Camera",images:[{url:"marker-red",alt:"Product front"}],price:408,currency:"USD"}, "\(layout)")])
            """
        case "product-horizontal-long", "product-compact-long":
            let layout = scenario == "product-horizontal-long" ? "horizontal" : "compact"
            return """
            root = Col([ProductCard({id:"camera",title:"Travel camera with a weather sealed body and a versatile lens for everyday photographs",images:[{url:"marker-red",alt:"Product front"}],specification:"Includes the camera, lens, battery and charger. The full supplied specification stays visible.",condition:"Returns within 30 days",availability:"Ships in 2 days",price:408,currency:"USD",priceNote:"Tax included",purchaseURL:"https://example.com/camera",actionLabel:"View offer"}, "\(layout)")])
            """
        case "product-album":
            return """
            root = Col([ProductCard({id:"camera",title:$title,images:[{url:"marker-red",alt:"Product front"},{url:"marker-blue",alt:"Product rear"}],price:408,currency:"USD",purchaseURL:"https://example.com/offer?variant=alpha%2Fbeta&opaque=A%3DB#details",actionLabel:"View offer"})])
            $title = "Camera"
            """
        default:
            preconditionFailure("Unknown ProductCard validation scenario: \(scenario)")
        }
    }

    private static func marker(red: CGFloat, blue: CGFloat) -> Image {
        guard let bitmap = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else {
            preconditionFailure("Cannot create ProductCard marker bitmap")
        }
        bitmap.setFillColor(CGColor(red: red, green: 0, blue: blue, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        guard let image = bitmap.makeImage() else { preconditionFailure("Cannot create ProductCard marker image") }
        return Image(decorative: image, scale: 1)
    }
}

/// The receipt observes real SDK state and delivered actions. It never invokes
/// the card's internal action or changes its local image selection.
@MainActor private struct GalleryProductValidationReceipt: View {
    @ObservedObject var model: GalleryProductValidationModel
    @ObservedObject var state: OpenUIState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.showsAlbumControls {
                Button("Update product title", action: model.updateTitle)
                    .accessibilityIdentifier("validation.product.update-title")
                Text(String(model.actions.count)).accessibilityIdentifier("validation.product.action-count")
                Text(model.actions.last?.type.displayString ?? "none").accessibilityIdentifier("validation.product.action-type")
                Text(model.lastURL).accessibilityIdentifier("validation.product.action-url")
                Text("\(state.sourceRevision)/\(state.presentationRevision)")
                    .accessibilityIdentifier("validation.product.document")
            }
            Text(state.errors.isEmpty && model.initialContractIssues.isEmpty
                 ? "none" : String(describing: state.errors) + " " + model.initialContractIssues.joined(separator: "; "))
                .accessibilityIdentifier("validation.product.errors")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
#endif
