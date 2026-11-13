import SwiftUI
import OpenUILang
import OpenUISwiftUI

enum ImageTextComponent {
    static var component: OpenUIComponent {
        let image = Parameter.objectSchema([("url", Parameter.stringSchema), ("alt", Parameter.stringSchema)], required: ["url", "alt"])
        let content = Parameter.objectSchema([("image", image)] + ["title", "body", "subtitle", "badge", "caption", "url"].map { ($0, Parameter.stringSchema) }, required: ["title"])
        return OpenUIComponent(name: "ImageText", description: "Editorial image and text. content requires title; image(url/alt), body/subtitle/badge/caption/url are optional. leading is an image/text row and top a cover; without an image no empty photo frame is added. Narrow/accessibility layouts may reflow vertically. Supplied URLs are preserved; no photo or facts are invented.", params: [
            ParamDef(name: "content", required: true, schema: content),
            OpenUIParameter.string("layout", required: false, values: ["leading", "top"]),
            OpenUIParameter.slot("footer", required: false)
        ]) { ImageTextView(context: $0) }
    }
}

private struct ImageTextView: View {
    @Environment(\.locale) private var locale
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutDirection) private var direction
    @State private var availableWidth: CGFloat = 0
    private func text(_ key: String) -> String { ValueReading.string(ValueReading.field(context.value("content"), key)) }
    private var image: Value? { ValueReading.field(context.value("content"), "image") }
    private var hasImage: Bool { !ValueReading.string(ValueReading.field(image, "url")).isEmpty }
    var body: some View {
        let horizontal = hasImage && context.string("layout") != "top" && !typeSize.isAccessibilitySize
            && (availableWidth == 0 || availableWidth >= EditorialMetrics.minimumRowWidth)
        let layout = horizontal
            ? AnyLayout(EditorialRowLayout(preferredImageWidth: EditorialMetrics.imageWidth, ratio: EditorialMetrics.imageAspectRatio,
                gap: theme.groupSpacing, rightToLeft: direction == .rightToLeft, idealWidth: EditorialMetrics.minimumRowWidth))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: theme.groupSpacing))
        return layout {
            ForEach(hasImage ? ["image", "content"] : ["content"], id: \.self) { item in
                if item == "image" { picture(ratio: horizontal ? EditorialMetrics.imageAspectRatio : theme.coverImageAspectRatio) }
                else { content }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            if width.isFinite, width > 0, abs(width - availableWidth) > 0.5 { availableWidth = width }
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
                    .buttonStyle(.plain).accessibilityHint(SDKStrings.text("imageText.openDetailHint", locale: locale))
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
