import SwiftLang
import SwiftUI

/// Report the label's natural width to Grid while allowing long labels to wrap.
private struct NativeEntityLabelLayout: Layout {
  let maximumWidth: CGFloat
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard let label = subviews.first else { return .zero }
    let ideal = label.sizeThatFits(.unspecified).width
    let proposed = proposal.width.flatMap { $0.isFinite ? max(1, $0) : nil } ?? maximumWidth
    let width = max(1, min(maximumWidth, proposed, ideal.isFinite ? max(1, ideal) : maximumWidth))
    let measured = label.sizeThatFits(ProposedViewSize(width: width, height: nil))
    return CGSize(width: width, height: measured.height)
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: nil))
  }
}

struct NativeEntityList: View {
  let context: OpenUIComponentContext
  @Namespace private var measurementScope
  @State private var availableWidth: CGFloat = 0
  private var labelWidthLimit: CGFloat {
    let width = availableWidth > 0 ? availableWidth : context.presentation.minimumTextColumnWidth * 2.5
    return max(1, width * 0.4)
  }
  var body: some View {
    Grid(alignment: .topLeading, horizontalSpacing: context.theme.spaceS, verticalSpacing: 0) {
      if context.string("size") != "small", let header = context.value("header"), header != .null {
        row(header, kind: .header)
        separator
      }
      let rows = context.children("rows")
      ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
        row(item.value, kind: .body)
        if index < rows.count - 1 {
          separator
        }
      }
      if context.string("size") != "small", let footer = context.value("footer"), footer != .null {
        separator
        row(footer, kind: .footer)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(GeometryReader { geometry in
      Color.clear.preference(key: NativeListContainerWidths.self, value: [measurementScope: geometry.size.width])
    })
    .onPreferenceChange(NativeListContainerWidths.self) { values in
      guard let width = values[measurementScope], width.isFinite, width > 0,
            abs(width - availableWidth) > 0.5 else { return }
      availableWidth = width
    }
  }
  private var separator: some View {
    Rectangle().fill(context.theme.borderDefault)
      .frame(height: context.presentation.borderWidth).gridCellUnsizedAxes(.horizontal).accessibilityHidden(true)
  }
  private enum RowKind { case header, body, footer }
  private func row(_ value: Value, kind: RowKind) -> some View {
    let small = context.string("size") == "small"
    let numeric = NativeValue.string(value, "rightVariant") == "number"
    return GridRow(alignment: .top) {
      NativeEntityLabelLayout(maximumWidth: labelWidthLimit) {
        NativeMarkdownText(text: NativeValue.string(value, "left") ?? "", mode: .inline,
          style: context.theme.entityLabelStyle(compact: small))
      }
        .padding(.vertical, context.theme.spacing(kind == .body ? "s" : "m"))
      NativeMarkdownText(text: NativeValue.string(value, "right") ?? "", mode: .inline,
        style: context.theme.entityValueStyle(compact: small, numeric: numeric,
          header: kind == .header, footer: kind == .footer))
      .multilineTextAlignment(numeric ? .trailing : .leading)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: numeric ? .trailing : .leading)
      .padding(.vertical, context.theme.spacing(kind == .body ? "s" : "m"))
    }
    .textSelection(.enabled)
    .accessibilityIdentifier("openui.entity-list.row")
  }
}

private struct NativeListPresentation {
  var imageWidth: CGFloat?
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
      imageWidth: imageList ? mediaLayout.imageWidth : 0,
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
  private var imageWidth: CGFloat { presentation.imageWidth ?? context.presentation.inlineThumbnailSize }
  private var hasImage: Bool {
    imageWidth > 0 && context.value("image") != nil && context.value("image") != .null
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
      NativeRemoteImage(
        src: NativeValue.string(image, "src"), alt: NativeValue.string(image, "alt") ?? "",
        layout: .thumbnail(CGSize(width: imageWidth, height: imageWidth))
      )
      .frame(width: imageWidth, height: imageWidth)
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
