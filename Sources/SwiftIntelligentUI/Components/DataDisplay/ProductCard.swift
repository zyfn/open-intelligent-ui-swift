import SwiftUI
import OpenUILang
import OpenUISwiftUI

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
        return OpenUIComponent(name: "ProductCard", description: "Universal consumer card for goods and bookable services/accommodation. price is the supplied nonnegative number or currency/amount string, e.g. 360 with currency CNY or ¥360; no 查询报价 prefix. Optional currency is a source ISO code, priceNote preserves units/conditions. priceText is legacy reader compatibility only, never new output. tags are short source-backed strings. No automatic 商品详情 bar: full specification and important condition/availability text remain visible, with caller-composed details only if needed. Price and primary action share a row with readable narrow/AX fallback. actionLabel defaults to 去购买; 去预订/查看房型 navigate the exact purchaseURL without submitting an order. Layout vertical uses3:2 media, horizontal/compact square thumbnails; Map has the same compact64pt summary with price/action. Loading shimmer/quiet retry and source metadata behavior are shared. No fabricated price, stock or conditions.", params: [
            ParamDef(name: "product", required: true, schema: product),
            OpenUIParameter.string("layout", required: false, values: ["vertical", "horizontal", "compact"]),
            OpenUIParameter.string("imageFit", required: false, values: ["cover", "contain"])
        ]) { context in
            if let product = ProductCardData(context.value("product")) {
                ProductCardView(context: context, product: product).id(product.id)
            } else {
                Text("商品资料不完整").foregroundStyle(.secondary)
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
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutDirection) private var direction
    @Environment(\.intelligentUIMapContent) private var inMap
    @State private var selectedImageURL: String?
    private var photoIndex: Int { product.images.firstIndex { $0.url == selectedImageURL } ?? 0 }
    private var photo: ProductCardData.Photo? { product.images.indices.contains(photoIndex) ? product.images[photoIndex] : nil }
    private var traceLayout: String {
        let value = context.string("layout") ?? "vertical"
        return ["vertical", "horizontal", "compact"].contains(value) ? value : "invalid"
    }

    @ViewBuilder var body: some View {
        if inMap { mapSummary }
        else { surface }
    }
    private var mapSummary: some View {
        HStack(alignment: .top, spacing: theme.controlHorizontalPadding) {
            picture(radius: theme.controlRadius, thumbnail: true)
                .frame(width: theme.mapThumbnailWidth, height: theme.mapThumbnailWidth)
            VStack(alignment: .leading, spacing: theme.spacingUnit) {
                Text(product.title).font(theme.mapCardTitleFont).foregroundStyle(theme.primaryText)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: theme.innerSpacing) {
                    VStack(alignment: .leading, spacing: theme.spacingUnit) {
                        Text(product.price.text ?? PricePresentation.missingLabel)
                            .font(theme.mapCardSecondaryFont.weight(.semibold)).foregroundStyle(theme.primaryText)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        if let note = product.price.note { Text(note).font(theme.captionFont).foregroundStyle(theme.secondaryText).lineLimit(1) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    purchaseAction(compact: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(theme.mapCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.canvas, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
    }
    private var surface: some View {
        Group {
            if context.string("layout") == "compact" && !typeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: theme.innerSpacing) {
                    picture(radius: theme.controlRadius, thumbnail: true).frame(width: theme.productCompactThumbnailWidth).fixedSize(horizontal: false, vertical: true)
                    information
                }.padding(theme.controlHorizontalPadding)
            } else if context.string("layout") == "horizontal" && !typeSize.isAccessibilitySize {
                ViewThatFits(in: .horizontal) {
                    EditorialRowLayout(preferredImageWidth: theme.productThumbnailWidth, ratio: 1, gap: theme.groupSpacing, rightToLeft: direction == .rightToLeft, idealWidth: max(1, theme.minimumImageTextRowWidth - 2 * theme.controlHorizontalPadding)) {
                        picture(radius: theme.controlRadius, thumbnail: true)
                        information
                    }.padding(theme.controlHorizontalPadding).frame(minWidth: theme.minimumImageTextRowWidth)
                    vertical
                }
            } else { vertical }
        }
        .intelligentUILayoutTrace("product-natural", "layout=\(traceLayout) ax=\(typeSize.isAccessibilitySize)")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .intelligentUILayoutTrace("product-frame", "layout=\(traceLayout) ax=\(typeSize.isAccessibilitySize)")
        .background(theme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius).strokeBorder(theme.separator.opacity(0.35)))
    }

    private var vertical: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                picture(radius: 0).fixedSize(horizontal: false, vertical: true)
                if product.images.count > 1 { imageControls.padding(theme.innerSpacing) }
            }
            information.padding(theme.controlHorizontalPadding)
        }.intelligentUILayoutTrace("product-vertical-stack")
    }
    private func picture(radius: CGFloat, thumbnail: Bool = false) -> some View {
        let contain = !thumbnail && context.string("imageFit") == "contain"
        return SourceImage(source: photo?.url, alt: photo?.alt ?? product.title,
                    ratio: thumbnail ? 1 : theme.productMediaAspectRatio, radius: radius, fit: contain ? .fit : .fill,
                    fillsContainBackground: contain)
    }
    private var imageControls: some View {
        HStack(spacing: 0) {
            Button { selectedImageURL = product.images[max(0, photoIndex - 1)].url } label: {
                Image(systemName: "chevron.left").frame(minWidth: theme.minimumControlHeight, minHeight: theme.minimumControlHeight)
            }.accessibilityLabel("上一张商品图片").disabled(photoIndex == 0)
            Button { selectedImageURL = product.images[min(product.images.count - 1, photoIndex + 1)].url } label: {
                Image(systemName: "chevron.right").frame(minWidth: theme.minimumControlHeight, minHeight: theme.minimumControlHeight)
            }.accessibilityLabel("下一张商品图片").disabled(photoIndex == product.images.count - 1)
        }
        .buttonStyle(.plain).foregroundStyle(theme.primaryText)
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
    @ViewBuilder private var title: some View {
        let text = Text(product.title).font(theme.titleFont).foregroundStyle(theme.primaryText).accessibilityAddTraits(.isHeader)
        if typeSize.isAccessibilitySize { text.fixedSize(horizontal: false, vertical: true) }
        else { text.lineLimit(2) }
    }
    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: theme.innerSpacing) { price; Spacer(minLength: theme.innerSpacing); action }
            VStack(alignment: .leading, spacing: theme.innerSpacing) { price; action }
        }
    }
    private var price: some View {
        VStack(alignment: .leading, spacing: theme.spacingUnit) {
            Text(product.price.text ?? PricePresentation.missingLabel)
                .font(product.price.text == nil ? theme.secondaryFont : theme.priceFont).monospacedDigit()
                .foregroundStyle(product.price.text == nil ? theme.secondaryText : theme.primaryText)
                .fixedSize(horizontal: product.price.canonical, vertical: true)
            if let note = product.price.note { Text(note).font(theme.captionFont).foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true) }
        }
    }
    private var action: some View { purchaseAction(compact: false) }
    @ViewBuilder private func purchaseAction(compact: Bool) -> some View {
        if let url = product.purchaseURL, SourceURL.isActionable(url) {
            PrimaryLinkButton(context: context, label: product.purchaseActionLabel, url: url, compact: compact, symbol: "arrow.up.right")
        }
    }
}
