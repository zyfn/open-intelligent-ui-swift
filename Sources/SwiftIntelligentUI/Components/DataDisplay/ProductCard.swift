import SwiftUI
import SwiftLang

private enum ProductCardMetrics {
    static let mediaAspectRatio: CGFloat = 1.5
    static let thumbnailWidth: CGFloat = 160
    static let compactThumbnailWidth: CGFloat = 76
    static let minimumRowWidth: CGFloat = 260
}

private struct ProductCardHorizontalLayout: Layout {
    let gap: CGFloat
    let idealWidth: CGFloat

    static var layoutProperties: LayoutProperties {
        var properties = LayoutProperties()
        properties.stackOrientation = .horizontal
        return properties
    }

    private func columns(width: CGFloat) -> (image: CGFloat, text: CGFloat) {
        let width = max(1, width)
        let image = min(ProductCardMetrics.thumbnailWidth, width * 0.34)
        return (image, max(1, width - image - max(0, gap)))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? idealWidth
        let columns = columns(width: width)
        let textHeight = subviews.count > 1 ? subviews[1].sizeThatFits(.init(width: columns.text, height: nil)).height : 0
        return CGSize(width: width, height: max(columns.image, textHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let columns = columns(width: bounds.width)
        let imageX = bounds.minX
        let textX = bounds.minX + columns.image + gap
        subviews[0].place(at: CGPoint(x: imageX, y: bounds.minY), anchor: .topLeading,
                          proposal: .init(width: columns.image, height: columns.image))
        subviews[1].place(at: CGPoint(x: textX, y: bounds.minY), anchor: .topLeading,
                          proposal: .init(width: columns.text, height: bounds.height))
    }
}

enum ProductCardComponent {
    static let optionalFields = ["specification", "merchant", "condition", "availability", "observedAt", "purchaseURL", "sourceURL", "actionLabel", "currency", "priceNote"]
    private static let string: JSONValue = .object([.init(key: "type", value: .string("string"))])
    private static func object(_ fields: [(String, JSONValue)], required: [String]) -> JSONValue {
        .object([.init(key: "type", value: .string("object")),
                 .init(key: "properties", value: .object(fields.map { .init(key: OpenUIString($0.0), value: $0.1) })),
                 .init(key: "required", value: .array(required.map { .string(OpenUIString($0)) })),
                 .init(key: "additionalProperties", value: .boolean(false))])
    }
    static var component: OpenUIComponent {
        let image = object([("url", string), ("alt", string)], required: ["url", "alt"])
        let product = object([
            ("id", string), ("title", string),
            ("images", .object([.init(key: "type", value: .string("array")), .init(key: "items", value: image)]))
        ] + [("price", PricePresentation.schema), ("priceText", PricePresentation.legacySchema), ("tags", Parameter.arraySchema(string))] + optionalFields.map { ($0, string) }, required: ["id", "title", "images"])
        return OpenUIComponent(name: "ProductCard", description: "Universal consumer card for goods and bookable services/accommodation. price is the supplied nonnegative number or currency/amount string, e.g. 360 with currency CNY or ¥360; no 查询报价 prefix. Optional currency is a source ISO code, priceNote preserves units/conditions. priceText is legacy reader compatibility only, never new output. tags are short source-backed strings. No automatic 商品详情 bar: full specification and important condition/availability text remain visible, with caller-composed details only if needed. Price and primary action share a row with readable narrow/AX fallback. actionLabel defaults to 去购买; 去预订/查看房型 navigate the exact purchaseURL without submitting an order. Layout vertical uses3:2 media, horizontal/compact square thumbnails. Loading shimmer/quiet retry and source metadata behavior are shared. No fabricated price, stock or conditions.", params: [
            ParamDef(name: "product", required: true, schema: product),
            OpenUIParameter.string("layout", required: false, values: ["vertical", "horizontal", "compact"]),
            OpenUIParameter.string("imageFit", required: false, values: ["cover", "contain"])
        ]) { context in
            if let product = ProductCardData(context.value("product")) {
                ProductCardView(context: context, product: product).id(product.id)
            } else {
                ProductUnavailableView()
            }
        }
    }
}

struct ProductCardData {
    struct Photo: Identifiable {
        let url: String
        let alt: String
        var id: String { url }
    }
    let id: String
    let title: String
    let specification: String?
    let images: [Photo]
    let merchant: String?
    let price: PricePresentation
    var priceText: String? { price.canonical ? price.text : price.legacyText }
    let tags: [String]
    let condition: String?
    let availability: String?
    let observedAt: String?
    let purchaseURL: String?
    let sourceURL: String?
    let actionLabel: String?
    var purchaseActionLabel: String { actionLabel ?? "去购买" }
    var imageAlbum: [ImageAlbumItem] { images.map { .init(source: $0.url, alt: $0.alt) } }

    init?(_ value: Value?) {
        guard let value, case .object(let fields) = value,
              !fields.fields.contains(where: { $0.key.displayString == "offers" }),
              let id = Self.string(value, "id"), let title = Self.string(value, "title"),
              case .array(let images) = Self.field(value, "images") else { return nil }
        self.id = id; self.title = title
        specification = Self.string(value, "specification")
        sourceURL = Self.string(value, "sourceURL")
        merchant = Self.string(value, "merchant")
        price = PricePresentation(value)
        var seenTags = Set<String>()
        tags = ValueReading.array(ValueReading.field(value, "tags")).compactMap { value in
            guard case .string(let label) = value, !label.displayString.isEmpty, seenTags.insert(label.displayString).inserted else { return nil }
            return label.displayString
        }
        condition = Self.string(value, "condition")
        availability = Self.string(value, "availability")
        observedAt = Self.string(value, "observedAt")
        purchaseURL = Self.string(value, "purchaseURL")
        actionLabel = Self.string(value, "actionLabel")
        var photoURLs = Set<String>()
        var photos: [Photo] = []
        for image in images {
            guard let url = Self.string(image, "url"), let alt = Self.string(image, "alt") else { return nil }
            if photoURLs.insert(url).inserted { photos.append(Photo(url: url, alt: alt)) }
        }
        self.images = photos
    }
    private static func field(_ value: Value, _ key: String) -> Value? {
        guard case .object(let object) = value else { return nil }
        return object.fields.last { $0.key == OpenUIString(key) }?.value
    }
    private static func string(_ value: Value, _ key: String) -> String? {
        guard case .string(let text) = field(value, key), !text.displayString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text.displayString
    }
}

private struct ProductCardView: View {
    let context: OpenUIComponentContext
    let product: ProductCardData
    @Environment(\.openIntelligentUITheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedImageURL: String?
    private var photoIndex: Int { product.images.firstIndex { $0.url == selectedImageURL } ?? 0 }
    private var photo: ProductCardData.Photo? { product.images.indices.contains(photoIndex) ? product.images[photoIndex] : nil }
    private var traceLayout: String {
        let value = context.string("layout") ?? "vertical"
        return ["vertical", "horizontal", "compact"].contains(value) ? value : "invalid"
    }

    @ViewBuilder var body: some View {
        surface
    }
    private var surface: some View {
        Group {
            if product.images.isEmpty {
                information.padding(theme.controlHorizontalPadding)
            } else if context.string("layout") == "compact" && !typeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: theme.innerSpacing) {
                    picture(radius: theme.controlRadius, thumbnail: true).frame(width: ProductCardMetrics.compactThumbnailWidth).fixedSize(horizontal: false, vertical: true)
                    information
                }.padding(theme.controlHorizontalPadding)
            } else if context.string("layout") == "horizontal" && !typeSize.isAccessibilitySize {
                ViewThatFits(in: .horizontal) {
                    ProductCardHorizontalLayout(gap: theme.groupSpacing,
                                                idealWidth: max(1, ProductCardMetrics.minimumRowWidth - 2 * theme.controlHorizontalPadding)) {
                        picture(radius: theme.controlRadius, thumbnail: true)
                        information
                    }.padding(theme.controlHorizontalPadding).frame(minWidth: ProductCardMetrics.minimumRowWidth)
                    vertical
                }
            } else { vertical }
        }
        .openIntelligentUILayoutTrace("product-natural", "layout=\(traceLayout) ax=\(typeSize.isAccessibilitySize)")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .openIntelligentUILayoutTrace("product-frame", "layout=\(traceLayout) ax=\(typeSize.isAccessibilitySize)")
        .background(theme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius).strokeBorder(theme.fieldBorder))
    }

    private var vertical: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                picture(radius: 0).fixedSize(horizontal: false, vertical: true)
                if product.images.count > 1 { imageControls.padding(theme.innerSpacing) }
            }
            information.padding(theme.controlHorizontalPadding)
        }.openIntelligentUILayoutTrace("product-vertical-stack")
    }
    private func picture(radius: CGFloat, thumbnail: Bool = false) -> some View {
        let contain = context.string("imageFit") == "contain"
        return SourceImage(source: photo?.url, alt: photo?.alt ?? product.title,
                    ratio: thumbnail ? 1 : ProductCardMetrics.mediaAspectRatio, radius: radius, fit: contain ? .fit : .fill,
                    fillsContainBackground: contain)
            .environment(\.openIntelligentUIImageAlbum, product.imageAlbum)
    }
    private var imageControls: some View {
        HStack(spacing: 0) {
            Button { selectedImageURL = product.images[max(0, photoIndex - 1)].url } label: {
                Image(systemName: "chevron.left").frame(minWidth: theme.minimumControlHeight, minHeight: theme.minimumControlHeight)
            }.accessibilityLabel(SDKStrings.text("product.previous_image", locale: locale)).disabled(photoIndex == 0)
            Button { selectedImageURL = product.images[min(product.images.count - 1, photoIndex + 1)].url } label: {
                Image(systemName: "chevron.right").frame(minWidth: theme.minimumControlHeight, minHeight: theme.minimumControlHeight)
            }.accessibilityLabel(SDKStrings.text("product.next_image", locale: locale)).disabled(photoIndex == product.images.count - 1)
        }
        .buttonStyle(QuietControlStyle(cornerRadius: 10_000)).foregroundStyle(theme.primaryText)
        .background(.regularMaterial, in: Capsule()).disabled(!context.canInteract)
    }
    private var information: some View {
        VStack(alignment: .leading, spacing: 0) {
          VStack(alignment: .leading, spacing: theme.innerSpacing) {
            title
            if !product.tags.isEmpty {
                WrappingRowLayout(gap: theme.innerSpacing, alignment: "center", justification: "start", wraps: true) {
                    ForEach(product.tags, id: \.self) { tag in
                        Text(tag).font(theme.captionFont.weight(.medium)).foregroundStyle(theme.primaryText)
                            .padding(.horizontal, theme.innerSpacing).padding(.vertical, theme.spacingUnit)
                            .background(theme.surface, in: Capsule())
                    }
                }
            }
            if let specification = product.specification {
                Text(specification).font(theme.secondaryFont).foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let merchant = product.merchant {
                Text(merchant).font(theme.captionFont).foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let limits = [product.condition, product.availability].compactMap { $0 }.joined(separator: " · ")
            if !limits.isEmpty { Text(limits).font(theme.captionFont).foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true) }
          }
            Spacer(minLength: theme.spacingUnit)
            footer
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var title: some View {
        Text(product.title).font(theme.titleFont).foregroundStyle(theme.primaryText)
            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
    }
    @ViewBuilder private var footer: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: theme.innerSpacing) { price(wrapping: true); action }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: theme.innerSpacing) { price(wrapping: false); Spacer(minLength: theme.innerSpacing); action }
                VStack(alignment: .leading, spacing: theme.innerSpacing) { price(wrapping: true); action }
            }
        }
    }
    private func price(wrapping: Bool) -> some View {
        VStack(alignment: .leading, spacing: theme.spacingUnit) {
            Text(product.price.displayText ?? SDKStrings.text("price.unknown", locale: locale))
                .font(product.price.text == nil ? theme.secondaryFont : theme.priceFont).monospacedDigit()
                .foregroundStyle(product.price.text == nil ? theme.secondaryText : theme.primaryText)
                .fixedSize(horizontal: !wrapping && product.price.canonical, vertical: true)
                .accessibilityLabel(product.price.accessibilityText(locale: locale) ?? SDKStrings.text("price.unknown", locale: locale))
            if let note = product.price.note { Text(note).font(theme.captionFont).foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true) }
            ForEach(product.price.diagnostics, id: \.self) { diagnostic in
                Label(diagnostic.message(locale: locale), systemImage: "exclamationmark.circle").font(theme.captionFont).foregroundStyle(theme.warning)
                    .fixedSize(horizontal: false, vertical: true).accessibilityHidden(product.price.text != nil)
            }
        }
    }
    @ViewBuilder private var action: some View {
        if let url = product.purchaseURL, SourceURL.isActionable(url) {
            let label = product.actionLabel ?? SDKStrings.text("product.buy", locale: locale)
            ActionButtonView(context: context, label: label, action: OpenUIActions.openURL(url), size: "sm")
                .accessibilityLabel(label)
        }
    }
}

private struct ProductUnavailableView: View {
    @Environment(\.locale) private var locale
    var body: some View { Text(SDKStrings.text("product.incomplete", locale: locale)).foregroundStyle(.secondary) }
}
