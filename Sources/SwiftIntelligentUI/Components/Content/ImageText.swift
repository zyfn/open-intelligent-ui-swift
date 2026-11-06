import SwiftUI
import OpenUILang
import OpenUISwiftUI

enum ImageTextComponent {
    static var component: OpenUIComponent {
        let image = Parameter.objectSchema([("url", Parameter.stringSchema), ("alt", Parameter.stringSchema)], required: ["url", "alt"])
        let content = Parameter.objectSchema([("image", image)] + ["title", "body", "subtitle", "badge", "caption", "url"].map { ($0, Parameter.stringSchema) }, required: ["title"])
        return OpenUIComponent(name: "ImageText", description: "Editorial image and text. content requires title; image(url/alt), body/subtitle/badge/caption/url are optional. leading is an image/text row and top a cover; without an image no empty photo frame is added. In Map the SDK always uses one compact summary card: square thumbnail, two-line title and one secondary line; top/leading, body/caption/footer do not expand that map summary. Put full place details outside Map. Elsewhere narrow/accessibility layouts may reflow vertically. Supplied URLs are preserved; no photo or facts are invented.", params: [
            ParamDef(name: "content", required: true, schema: content),
            OpenUIParameter.string("layout", required: false, values: ["leading", "top"]),
            OpenUIParameter.slot("footer", required: false)
        ]) { ImageTextView(context: $0) }
    }
}

private struct ImageTextView: View {
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutDirection) private var direction
    @Environment(\.intelligentUIMapContent) private var inMap
    private func text(_ key: String) -> String { ValueReading.string(ValueReading.field(context.value("content"), key)) }
    private var image: Value? { ValueReading.field(context.value("content"), "image") }
    private var hasImage: Bool { !ValueReading.string(ValueReading.field(image, "url")).isEmpty }
    var body: some View {
        if inMap { mapSummary }
        else if !hasImage { content }
        else if context.string("layout") == "top" || typeSize.isAccessibilitySize { vertical }
        else {
            ViewThatFits(in: .horizontal) {
                EditorialRowLayout(preferredImageWidth: theme.editorialImageWidth, ratio: theme.editorialImageAspectRatio, gap: theme.groupSpacing, rightToLeft: direction == .rightToLeft, idealWidth: theme.minimumImageTextRowWidth) {
                    picture(ratio: theme.editorialImageAspectRatio)
                    content
                }.frame(minWidth: theme.minimumImageTextRowWidth)
                vertical
            }
        }
    }
    private var mapSummary: some View {
        HStack(alignment: .top, spacing: theme.controlHorizontalPadding) {
            Group {
                if hasImage { picture(ratio: 1) }
                else {
                    Image(systemName: "mappin.and.ellipse").font(theme.bodyFont).foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(theme.surface)
                }
            }
            .frame(width: theme.mapThumbnailWidth, height: theme.mapThumbnailWidth)
            .clipShape(RoundedRectangle(cornerRadius: theme.controlRadius))
            VStack(alignment: .leading, spacing: theme.spacingUnit) {
                if SourceURL.isActionable(text("url")) {
                    OpenUIActionSurface(context: context, action: OpenUIActions.openURL(text("url")), useNativeStyle: true) { mapTitle }.buttonStyle(.plain)
                } else { mapTitle }
                let secondary = [text("badge"), text("subtitle")].filter { !$0.isEmpty }.joined(separator: " · ")
                if !secondary.isEmpty { Text(secondary).font(theme.mapCardSecondaryFont).foregroundStyle(theme.secondaryText).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(theme.mapCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.canvas, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
    }
    private var mapTitle: some View {
        Text(text("title")).font(theme.mapCardTitleFont).foregroundStyle(theme.primaryText)
            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
    }
    private var vertical: some View {
        VStack(alignment: .leading, spacing: theme.groupSpacing) {
            picture(ratio: theme.coverImageAspectRatio).fixedSize(horizontal: false, vertical: true)
            content
        }
    }
    private func picture(ratio: CGFloat) -> some View {
        SourceImage(source: ValueReading.string(ValueReading.field(image, "url")),
                    alt: ValueReading.string(ValueReading.field(image, "alt")), ratio: ratio, radius: theme.cornerRadius, fit: .fill)
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: theme.innerSpacing) {
            if SourceURL.isActionable(text("url")) {
                OpenUIActionSurface(context: context, action: OpenUIActions.openURL(text("url")), useNativeStyle: true) { title }
                    .buttonStyle(.plain).accessibilityHint("查看详情")
            } else { title }
            if !text("badge").isEmpty {
                Text(text("badge")).font(theme.captionFont.weight(.medium)).padding(.horizontal, theme.innerSpacing).padding(.vertical, theme.spacingUnit)
                    .background(theme.surface, in: Capsule())
            }
            if !text("subtitle").isEmpty { Text(text("subtitle")).font(theme.secondaryFont).foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true) }
            if !text("body").isEmpty { RichMarkdown(context: context, text: text("body"), compact: true) }
            if !text("caption").isEmpty { Text(text("caption")).font(theme.captionFont).foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true).lineSpacing(theme.bodyLineSpacing / 2) }
            context.slot("footer")
        }
    }
    private var title: some View { Text(text("title")).font(theme.titleFont).foregroundStyle(theme.primaryText).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader) }
}
