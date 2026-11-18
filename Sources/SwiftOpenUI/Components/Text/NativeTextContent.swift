import SwiftLang
import SwiftUI

struct NativeHeading: View {
  let context: OpenUIComponentContext
  let compact: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: context.theme.componentStyle.titleDetailGap) {
      if let title = context.string(compact ? "heading" : "title"),
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(title).nativeTextStyle(compact ? context.theme.objectTitleStyle() : context.theme.sectionTitleStyle()).accessibilityAddTraits(
          .isHeader)
      }
      if let detail = context.string(compact ? "description" : "subtitle"),
        !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(detail).nativeTextStyle(context.theme.textStyle(.supporting))
      }
    }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct NativeMarkdown: View {
  let context: OpenUIComponentContext
  var body: some View {
    let surface = NativeContentSurface(context.string("variant"), fallback: .clear)
    NativeMarkdownText(text: context.string("textMarkdown") ?? "")
      .padding(
        context.string("variant") == "clear" || context.string("variant") == nil
          ? 0 : context.theme.spaceM
      )
      .background(
        surface.fill(context.theme),
        in: RoundedRectangle(cornerRadius: context.theme.radiusM))
      .overlay {
        RoundedRectangle(cornerRadius: context.theme.radiusM)
          .strokeBorder(surface.bordered
            ? context.presentation.resolvedCardBorderColor(with: context.theme) : .clear,
            lineWidth: context.presentation.borderWidth)
          .allowsHitTesting(false)
      }
  }
}

private func semanticColor(_ variant: String?, theme: OpenUIThemeValues) -> Color {
  switch variant {
  case "danger", "error": return theme.textDangerPrimary
  case "success": return theme.textSuccessPrimary
  case "warning": return theme.textAlertPrimary
  case "info": return theme.textInfoPrimary
  default: return theme.textNeutralSecondary
  }
}

struct NativeCallout: View {
  let context: OpenUIComponentContext
  let reactive: Bool
  private var binding: Binding<Value>? { reactive ? context.binding("visible") : nil }
  private var visible: Bool {
    binding.map { $0.wrappedValue == .boolean(true) || $0.wrappedValue == .string("true") } ?? true
  }
  var authoredTitle: String? { authoredCopy(context.string("title")) }
  var authoredDescription: String? { authoredCopy(context.string("description")) }
  var statusIcon: String? {
    switch context.string("variant") {
    case "success": return "checkmark.circle"
    case "warning": return "exclamationmark.circle"
    case "error", "danger": return "xmark.circle"
    default: return nil
    }
  }
  private var hasCopy: Bool {
    authoredTitle != nil || authoredDescription != nil
  }
  private func authoredCopy(_ text: String?) -> String? {
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return text
  }
  var body: some View {
    Group {
      if visible && hasCopy {
        HStack(alignment: .firstTextBaseline, spacing: context.theme.spaceM) {
          if let statusIcon {
            Image(systemName: statusIcon)
              .openUIFont(context.theme.textLabelDefaultHeavy, role: .control)
              .foregroundStyle(semanticColor(context.string("variant"), theme: context.theme))
              .accessibilityHidden(true)
          }
          VStack(alignment: .leading, spacing: context.theme.componentStyle.titleDetailGap) {
            if let title = authoredTitle {
              Text(title).openUIFont(context.theme.textBodyDefaultHeavy, role: .title)
                .foregroundStyle(context.theme.textNeutralPrimary)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let detail = authoredDescription {
              NativeMarkdownText(text: detail, style: context.theme.textStyle(.body).richText())
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, statusIcon == nil ? context.theme.spaceML : 0)
        .padding(.vertical, context.theme.spaceS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
          if statusIcon == nil {
            RoundedRectangle(cornerRadius: context.theme.radius3xs, style: .continuous)
              .fill(context.theme.borderDefault).frame(width: 3)
              .padding(.vertical, context.theme.space2xs).accessibilityHidden(true)
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(statusLabel, bundle: NativeControlResources.bundle))
      }
    }.task(id: "\(context.presentationSourceRevision):\(visible):\(context.canInteract)") {
      guard visible, context.canInteract, binding != nil else { return }
      do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
      guard !Task.isCancelled else { return }
      binding?.wrappedValue = .boolean(false)
    }
  }
  private var statusLabel: LocalizedStringKey {
    switch context.string("variant") {
    case "success": return "Success"
    case "warning": return "Warning"
    case "error", "danger": return "Error"
    default: return "Information"
    }
  }
}

/// The upstream TextBlock family renders inline Markdown. Keep this native
/// presentation adapter shared; it does not interpret or rewrite OpenUI Lang.
enum NativeInlineMarkdown {
  static func attributed(_ value: String) -> AttributedString {
    (try? AttributedString(
      markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(value)
  }
  static func text(_ value: String) -> Text { Text(attributed(value)) }
}

struct NativeInlineText: View {
  let context: OpenUIComponentContext
  let bold: Bool
  private var style: NativeRichTextStyle {
    context.theme.inlineTextStyle(context.string("size") ?? "sm",
      emphasized: bold, numeric: context.string("variant") == "number")
  }
  var body: some View {
    VStack(alignment: .leading, spacing: context.theme.componentStyle.titleDetailGap) {
      NativeMarkdownText(text: context.string("value") ?? "", mode: .inline, style: style)
      if let sub = context.string("subtext"), !sub.isEmpty {
        NativeMarkdownText(text: sub, mode: .inline,
          style: context.theme.textStyle(.supporting).richText(
            numeric: context.string("subtextVariant") == "number", color: subtextColor(sub)))
      }
    }.fixedSize(horizontal: false, vertical: true)
  }
  private func subtextColor(_ value: String) -> Color {
    guard context.string("subtextVariant") == "metric" else { return context.theme.textNeutralSecondary }
    if value.hasPrefix("+") { return semanticColor("success", theme: context.theme) }
    if value.hasPrefix("-") { return semanticColor("danger", theme: context.theme) }
    return context.theme.textNeutralSecondary
  }
}

struct NativeMediaText: View {
  @Environment(\.openUICardMediaInset) private var cardMediaInset
  @Environment(\.multilineTextAlignment) private var textAlignment
  @ScaledMetric(relativeTo: .body) private var iconScale: CGFloat = 1
  enum Media { case icon, thumbnail, banner }
  let context: OpenUIComponentContext
  let media: Media
  private var vertical: Bool { context.string("layout") == "vertical" }
  private var centered: Bool { vertical && textAlignment == .center }
  private var adaptiveThumbnail: NativeAdaptiveThumbnail? {
    guard media == .thumbnail, explicitImageSize == nil else { return nil }
    return .init(preferred: imageSize,
      minimum: context.presentation.minimumInlineThumbnailSize,
      readingWidth: context.presentation.minimumTextColumnWidth * iconScale)
  }
  var body: some View {
    Group {
      if media == .banner {
        VStack(alignment: .leading, spacing: context.theme.spaceM) {
          NativeRemoteImage(
            src: context.string("src"), alt: context.string("alt") ?? context.string("title") ?? "",
            layout: .aspect(context.presentation.coverAspectRatio))
            .clipShape(NativeCardTopMediaShape(radius: cardMediaInset > 0 ? context.theme.radius3xl : context.theme.radiusM,
              topOnly: cardMediaInset > 0))
            .padding(.horizontal, -cardMediaInset)
            .padding(.top, -cardMediaInset)
          words
        }.frame(maxWidth: .infinity, alignment: .leading)
      } else {
        NativeMediaRow(axis: vertical ? .vertical : .horizontal,
          gap: context.theme.spaceM * (media == .icon ? iconScale : 1),
          centered: vertical ? centered : media != .icon,
          adaptiveThumbnail: adaptiveThumbnail,
          media: { leadingMedia }, copy: {
            words.frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
              .multilineTextAlignment(centered ? .center : .leading)
          })
      }
    }
  }
  @ViewBuilder private var leadingMedia: some View {
    if media == .icon {
      let style = NativeIconTextStyle(variant: context.presentationString("iconVariant"), theme: context.theme)
      context.slot("icon").environment(\.openUIIconSize, glyphSize)
        .foregroundStyle(style.foreground)
        .frame(width: (glyphSize + style.inset * 2) * iconScale, height: (glyphSize + style.inset * 2) * iconScale)
        .background(style.background,
          in: RoundedRectangle(cornerRadius: context.theme.radiusM))
        .accessibilityIdentifier("openui.icon-text.badge")
    } else {
      NativeRemoteImage(
        src: context.string("src"), alt: context.string("alt") ?? context.string("title") ?? "",
        layout: explicitImageSize.map { .thumbnail(CGSize(width: $0, height: $0)) } ?? .aspect(1))
        .frame(idealWidth: imageSize)
        .clipShape(RoundedRectangle(cornerRadius: context.theme.radiusM, style: .continuous))
    }
  }
  private var glyphSize: CGFloat { NativeIconTextMetrics.glyph(context.presentationString("iconSize")) }
  private var explicitImageSize: CGFloat? {
    if let size = context.presentationNumber("imageSize"), size.isFinite, size > 0 { return CGFloat(size) }
    return nil
  }
  private var imageSize: CGFloat {
    if let explicitImageSize { return explicitImageSize }
    let preferred = context.presentation.inlineThumbnailSize
    return preferred.isFinite && preferred > 0 ? preferred : OpenUIPresentation.defaults.inlineThumbnailSize
  }
  private var words: some View {
    VStack(alignment: centered ? .center : .leading, spacing: context.theme.componentStyle.titleDetailGap) {
      if let title = context.string("title"), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        NativeMarkdownText(text: title, mode: .inline,
          style: context.theme.objectTitleStyle(emphasized: media == .banner || context.flag("bold") == true).richText())
      }

      if let sub = context.string("subtitle"), !sub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        NativeMarkdownText(text: sub, mode: .inline, style: context.theme.textStyle(.supporting).richText())
      }
    }.fixedSize(horizontal: false, vertical: true)
  }
}

struct NativeTag: View {
  let context: OpenUIComponentContext
  var body: some View {
    NativeTagPill(text: context.string("text") ?? "", size: context.string("size"),
      variant: context.string("variant"), theme: context.theme) { context.slot("icon") }
  }
}

struct NativeTagBlock: View {
  let context: OpenUIComponentContext
  var body: some View {
    NativeWrappingRow(gap: context.theme.spacing("s")) {
      ForEach(context.children("tags")) { tag in
        NativeTagPill(text: NativeValue.string(tag.value), size: context.string("size"),
          variant: nil, theme: context.theme) { EmptyView() }
      }
    }
  }
}
