import SwiftLang
import SwiftUI

struct NativeEntityList: View {
  let context: OpenUIComponentContext
  private var compact: Bool { context.string("size") == "small" }

  var body: some View {
    let rows = context.children("rows")
    let header = compact ? nil : context.value("header")
    let footer = compact ? nil : context.value("footer")
    let hasFooter = footer != nil && footer != .null

    VStack(alignment: .leading, spacing: 0) {
      if let header, header != .null {
        row(header, kind: .header)
        if !rows.isEmpty || hasFooter { separator }
      }
      ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
        row(item.value, kind: .body)
        if index < rows.count - 1 || hasFooter { separator }
      }
      if let footer, hasFooter { row(footer, kind: .footer) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var separator: some View {
    Rectangle().fill(context.theme.borderDefault)
      .frame(height: context.presentation.borderWidth).accessibilityHidden(true)
  }

  private enum RowKind { case header, body, footer }

  private func row(_ value: Value, kind: RowKind) -> some View {
    let numeric = NativeValue.string(value, "rightVariant") == "number"
    let header = kind == .header
    return OpenUIFlexLayout(direction: "row", gap: context.theme.spaceM,
      align: "start", justify: "between", wrap: false) {
      NativeMarkdownText(text: NativeValue.string(value, "left") ?? "", mode: .inline,
        style: context.theme.entityLabelStyle(compact: compact, header: header))
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .layoutValue(key: OpenUIFlexGrowKey.self, value: true)
      NativeMarkdownText(text: NativeValue.string(value, "right") ?? "", mode: .inline,
        style: context.theme.entityValueStyle(compact: compact, numeric: numeric,
          header: header, footer: kind == .footer))
        .multilineTextAlignment(.trailing)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
        .layoutValue(key: OpenUIFlexGrowKey.self, value: true)
    }
    .padding(.vertical, context.theme.spaceM)
    .textSelection(.enabled)
    .accessibilityIdentifier("openui.entity-list.row")
  }
}

private struct NativeListPresentation {
  var imageSize: CGSize?
  var compact = false
  var axis = NativeMediaRowAxis.horizontal
}

private struct NativeListPresentationKey: EnvironmentKey {
  static let defaultValue = NativeListPresentation()
}

extension EnvironmentValues {
  fileprivate var openUIListPresentation: NativeListPresentation {
    get { self[NativeListPresentationKey.self] }
    set { self[NativeListPresentationKey.self] = newValue }
  }
}

struct NativeListBlock: View {
  let context: OpenUIComponentContext
  @Environment(\.displayScale) private var displayScale
  @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1
  @Namespace private var scope
  @State private var containerWidth: CGFloat?
  private var imageList: Bool { context.string("variant") == "image" }
  private var compact: Bool { context.string("size") == "small" }
  private var mediaLayout: NativeListMediaLayout {
    NativeListMediaLayout(width: containerWidth,
      preferredImageWidth: compact ? context.presentation.compactThumbnailSize : context.presentation.thumbnailSize,
      minimumImageWidth: context.presentation.inlineThumbnailSize,
      textWidth: context.presentation.minimumTextColumnWidth * textScale,
      gap: context.theme.spaceM)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(context.children("items").enumerated()), id: \.element.id) { index, item in
        if index > 0 {
          Rectangle().fill(context.theme.borderDefault).frame(height: 1 / displayScale)
            .padding(.vertical, context.theme.spacing(compact ? "s" : "m"))
        }
        HStack(alignment: .top, spacing: context.theme.spaceM) {
          if !imageList {
            Text("\(index + 1)").openUIFont(context.theme.textBodySm.monospacedDigit()).foregroundStyle(
              context.theme.textNeutralSecondary
            ).frame(minWidth: 22)
          }
          context.render(item.value)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(GeometryReader { geometry in
      Color.clear.preference(key: NativeListContainerWidths.self, value: [scope: geometry.size.width])
    })
    .onPreferenceChange(NativeListContainerWidths.self) { values in
      guard let width = values[scope], width.isFinite, width > 0 else { return }
      if containerWidth.map({ abs($0 - width) > 0.5 }) ?? true { containerWidth = width }
    }
    .environment(\.openUIListPresentation, NativeListPresentation(
      imageSize: imageList ? mediaLayout.imageSize : .zero,
      compact: compact, axis: mediaLayout.axis))
  }
}

private struct NativeListContainerWidths: PreferenceKey {
  static let defaultValue: [Namespace.ID: CGFloat] = [:]
  static func reduce(value: inout [Namespace.ID: CGFloat], nextValue: () -> [Namespace.ID: CGFloat]) {
    value.merge(nextValue(), uniquingKeysWith: { _, next in next })
  }
}

struct NativeListItem: View {
  let context: OpenUIComponentContext
  @Environment(\.openUIListPresentation) private var presentation
  private var imageSize: CGSize {
    let side = context.presentation.inlineThumbnailSize
    return presentation.imageSize ?? CGSize(width: side, height: side)
  }
  private var hasImage: Bool {
    imageSize.width > 0 && context.value("image") != nil && context.value("image") != .null
  }
  private var hasAction: Bool {
    context.value("action") != nil && context.value("action") != .null
  }
  var body: some View {
    Group {
      if hasAction {
        OpenUIActionSurface(
          context: context, message: context.string("title") ?? "", action: context.value("action")
        ) { content }
      } else {
        content
      }
    }
  }
  @ViewBuilder private var content: some View {
    Group {
      if hasImage {
        NativeMediaRow(axis: presentation.axis, gap: context.theme.spaceM,
          media: { photo }, copy: { words })
      } else { words }
    }.fixedSize(horizontal: false, vertical: true).contentShape(Rectangle())
  }
  @ViewBuilder private var photo: some View {
    if let image = context.value("image"), image != .null {
      let size = imageSize
      NativeRemoteImage(
        src: NativeValue.string(image, "src"), alt: NativeValue.string(image, "alt") ?? "",
        layout: .thumbnail(size)
      )
      .frame(width: size.width, height: size.height)
      .clipShape(RoundedRectangle(cornerRadius: context.theme.radiusM, style: .continuous))
    }
  }
  private var words: some View {
    HStack(alignment: .center, spacing: context.theme.spaceM) {
      VStack(alignment: .leading, spacing: context.theme.componentStyle.titleDetailGap) {
        Text(context.string("title") ?? "").openUIFont(presentation.compact
          ? context.theme.textBodySmHeavy : context.theme.textBodyDefaultHeavy, role: .title)
        if let detail = context.string("subtitle") {
          Text(detail).nativeTextStyle(context.theme.textStyle(.supporting))
        }
        if hasAction, let label = context.string("actionLabel"), !label.isEmpty {
          Text(label).nativeTextStyle(context.theme.textStyle(.compactAction))
            .padding(.top, 2).accessibilityHidden(true)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
      if hasAction {
        Image(systemName: "chevron.right").openUIFont(context.theme.textBodyXs.weight(.semibold))
          .foregroundStyle(context.theme.textNeutralSecondary).accessibilityHidden(true)
      }
    }.fixedSize(horizontal: false, vertical: true)
  }
}

struct NativeSteps: View {
  let context: OpenUIComponentContext
  @Environment(\.displayScale) private var displayScale
  @ScaledMetric(relativeTo: .body) private var markerDiameter: CGFloat = 28
  @ScaledMetric(relativeTo: .body) private var timelineMarker: CGFloat = 12
  @ScaledMetric(relativeTo: .body) private var timelineLane: CGFloat = 16
  var body: some View {
    let items = context.children("items")
    // A trailing optional variant is unknown until its argument or the call
    // closes. Show arriving text without guessing a numbered/timeline marker.
    let variantReady = context.layoutConfigurationReady
    // If generation has stopped without deciding the trailing variant, keep
    // completed items readable using the component's default numbered style.
    let showMarkers = variantReady || context.hasInterruptedData || (!context.isStreaming && !context.hasPendingData)
    let timeline = variantReady && context.presentationString("variant") == "timeline"
    return VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
        HStack(alignment: .top, spacing: timeline ? context.theme.spaceS : context.theme.spacing("m")) {
          Group {
            if !showMarkers {
              Color.clear.frame(width: markerDiameter, height: markerDiameter).accessibilityHidden(true)
            } else if timeline {
              Circle().strokeBorder(context.theme.textNeutralLink, lineWidth: 2)
                .frame(width: timelineMarker, height: timelineMarker)
                .padding(.top, context.theme.space2xs)
                .frame(width: timelineLane)
                .accessibilityHidden(true)
            } else {
              NativeStepMarker(number: index + 1, theme: context.theme, diameter: markerDiameter)
            }
          }
          if timeline {
            VStack(alignment: .leading, spacing: context.theme.space2xs) {
              if let time = NativeStepsTimeline.time(item.value), !time.isEmpty {
                Text(time).openUIFont(context.theme.textBodySm, role: .detail)
                  .foregroundStyle(index == 0 ? context.theme.textNeutralLink : context.theme.textNeutralSecondary)
              }
              Text(NativeValue.string(item.value, "title") ?? "")
                .openUIFont(context.theme.textHeadingXs, role: .title)
                .foregroundStyle(context.theme.textNeutralPrimary)
                .fixedSize(horizontal: false, vertical: true)
              NativeMarkdownText(text: NativeValue.string(item.value, "details") ?? "",
                style: context.theme.textStyle(.supporting).richText())
            }.frame(maxWidth: .infinity, alignment: .leading)
          } else {
            VStack(alignment: .leading, spacing: context.theme.spacing("xs")) {
              Text(NativeValue.string(item.value, "title") ?? "").openUIFont(context.theme.textBodyDefaultHeavy, role: .title)
              NativeMarkdownText(text: NativeValue.string(item.value, "details") ?? "",
                style: context.theme.textStyle(.body).richText())
            }
          }
        }
        .padding(.bottom, index < items.count - 1 ? (timeline ? context.theme.spaceL : context.theme.spacing("m")) : 0)
        .background(alignment: .topLeading) {
          if showMarkers && index < items.count - 1 {
            Rectangle().fill(context.theme.borderInteractive)
              .frame(width: 1.5 / displayScale)
              .padding(.top, timeline ? timelineMarker + context.theme.space2xs : markerDiameter + context.theme.spacing("xs"))
              .offset(x: timeline ? timelineLane / 2 : markerDiameter / 2)
              .accessibilityHidden(true)
          }
        }
      }
    }
  }
}

/// A time label is displayed only after the complete positional argument has
/// arrived, so an unfinished clock value is not presented as a fact.
enum NativeStepsTimeline {
  static func time(_ value: Value) -> String? {
    guard case .element(let item) = value, item.sourceReadiness["time"].complete else { return nil }
    return PropValue.string(item, "time")
  }
}

/// The badge follows its text's measured size, including custom fonts and Dynamic Type.
struct NativeStepMarker: View {
  let number: Int
  let theme: OpenUIThemeValues
  let diameter: CGFloat
  var body: some View {
    Text("\(number)").openUIFont(theme.textBodySmHeavy, role: .detail)
      .fixedSize().frame(minWidth: diameter, minHeight: diameter)
      .background(theme.sunk, in: Circle())
      .accessibilityIdentifier("openui.steps.marker")
  }
}
