import SwiftLang
import SwiftUI

private struct NativeCardActionKey: EnvironmentKey {
  static let defaultValue = false
}

fileprivate struct NativeCardGroupAction {
  let message: String
  let action: Value
}

private struct NativeCardGroupActionKey: EnvironmentKey {
  static let defaultValue: NativeCardGroupAction? = nil
}

extension EnvironmentValues {
  fileprivate var openUICardGroupAction: NativeCardGroupAction? {
    get { self[NativeCardGroupActionKey.self] }
    set { self[NativeCardGroupActionKey.self] = newValue }
  }
  var openUICardIsAction: Bool {
    get { self[NativeCardActionKey.self] }
    set { self[NativeCardActionKey.self] = newValue }
  }
}

struct NativeCardItem: View {
  let context: OpenUIComponentContext
  let kind: String
  private var summary: Bool { kind == "Overview" || kind == "Snippet" }
  private var centeredOverview: Bool {
    guard kind == "Overview", case .element(let top) = context.value("top") else { return false }
    return ["IconText", "ImageText"].contains(top.typeName) && PropValue.string(top, "layout") == "vertical"
  }
  private var copyAlignment: Alignment { centeredOverview ? .center : .leading }
  private var itemTheme: OpenUIThemeValues {
    var theme = context.theme
    // The official families share tokens, not an identical outline: Context
    // uses radius-xl, compact fact cards radius-2xl, photo cards radius-3xl.
    theme.radius3xl = context.theme.cardRadius(for: kind)
    // Insets are owned by the component recipe; do not mutate a shared spacing token.
    return theme
  }
  @Environment(\.openUICardIsAction) private var isAction
  @Environment(\.openUICardGroupAction) private var pendingGroupAction
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.openUIResourceContext) private var artworkResources
  @Environment(\.openUIMediaCache) private var artworkCache
  @State private var artworkImageState: NativeArtworkImageState?
  @State private var artworkPicture: Image?
  @State private var artworkAttempt = 0
  @State private var copyBelowArtwork = false
  @Namespace private var artworkLayoutScope
  private var groupAction: NativeCardGroupAction? { pendingGroupAction }
  private var snippetValueNeedsUnbrokenWidth: Bool {
    guard case .element(let rhs) = context.value("rhs") else { return false }
    if ["Text", "BoldText"].contains(rhs.typeName) { return PropValue.string(rhs, "variant") == "number" }
    return true
  }
  private var contentInset: CGFloat {
    kind == "Composite" ? context.theme.componentStyle.panelInset : context.theme.componentStyle.objectInset
  }
  private var artworkSource: String? {
    guard ["Visual", "Context"].contains(kind), let source = context.string("bgImageSrc"),
      !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return source
  }
  private var artworkTarget: NativeMediaResourceTarget? {
    guard let source = artworkSource else { return nil }
    return .init(source: source, resources: artworkResources, attempt: artworkAttempt)
  }
  private var hasLoadedArtwork: Bool {
    guard context.element.sourceReadiness["bgImageSrc"].complete,
      let target = artworkTarget, target.isCurrent else { return false }
    return target.cachedImage(in: artworkCache) != nil
      || (artworkImageState?.target == target && artworkImageState?.status == .loaded)
  }
  private var displayedArtwork: Image? {
    guard hasLoadedArtwork, let target = artworkTarget else { return nil }
    if artworkImageState?.target == target, artworkImageState?.status == .loaded, let artworkPicture { return artworkPicture }
    return target.cachedImage(in: artworkCache)?.image
  }
  private var usesArtworkOverlay: Bool {
    hasLoadedArtwork && !typeSize.isAccessibilitySize && !copyBelowArtwork
  }
  private var contentTheme: OpenUIThemeValues {
    var theme = context.theme
    if usesArtworkOverlay {
      theme.textNeutralPrimary = .white
      theme.textNeutralSecondary = .white.opacity(0.86)
      theme.sunk = .black.opacity(0.55)
      theme.foreground = .black.opacity(0.75)
      theme.borderDefault = .white.opacity(0.2)
      theme.background = .black
    }
    return theme
  }
  @ViewBuilder private var actionIndicator: some View {
    if isAction {
      Image(systemName: "chevron.right").openUIFont(context.theme.textLabelSmHeavy, role: .control)
        .foregroundStyle(contentTheme.textNeutralSecondary).accessibilityHidden(true)
    }
  }
  var body: some View {
    Group {
      if summary { content }
      else { content.clipShape(RoundedRectangle(cornerRadius: itemTheme.radius3xl, style: .continuous)) }
    }
    // Artwork contrast belongs to the inline copy. Presentations must inherit
    // the reader's appearance rather than this local dark treatment.
    .environment(\.openUITheme, contentTheme)
    .environment(\.colorScheme, usesArtworkOverlay ? .dark : colorScheme)
    .foregroundStyle(contentTheme.textNeutralPrimary)
    .modifier(NativeImageInteraction(source: artworkSource,
      image: displayedArtwork,
      alt: context.string("bgImageAlt") ?? "", enabled: artworkSource != nil && context.canInteract,
      failed: artworkImageState?.target == artworkTarget && artworkImageState?.status == .unavailable,
      previewTheme: context.theme, retry: { artworkAttempt += 1 }))
    .modifier(NativeCardSurface(
      theme: itemTheme,
      // Facts are outlined without a fill so they stay part of the reply;
      // independent offers keep the raised surface. Explicit gray and artwork
      // treatments remain item properties.
      fill: artworkSource != nil ? .clear
        : context.string("bgColor") == "gray" ? context.theme.sunk
        : summary ? .clear : context.theme.foreground,
      bordered: artworkSource == nil && kind != "Context"))
    .environment(\.openUIActionDensity, .compact)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("openui.card-item." + kind.lowercased())
    .layoutValue(key: OpenUIFlexGrowKey.self, value: true)
  }
  @ViewBuilder private var content: some View {
      if let source = artworkSource, let target = artworkTarget {
        NativeArtworkCardLayout(aspectRatio: context.presentation.coverAspectRatio,
          fallbackWidth: context.presentation.minimumCardWidth, accessibility: typeSize.isAccessibilitySize) {
          ZStack {
            context.theme.sunk
            NativeRemoteImage(src: source, alt: context.string("bgImageAlt") ?? "", layout: .cover, attempt: artworkAttempt,
              onStatus: { status, image in
                guard context.isCurrentPresentation, target.isCurrent else { return }
                if let image { artworkPicture = image }
                let next = NativeArtworkImageState(target: target, status: status)
                if artworkImageState != next { artworkImageState = next }
              }, interactionEnabled: false)
              .environment(\.openUITheme, context.theme)
              .environment(\.colorScheme, colorScheme)
              .environment(\.openUIMediaSourceReady, context.element.sourceReadiness["bgImageSrc"].complete)
          }.allowsHitTesting(false)
          copy.background {
            GeometryReader { geometry in
              Color.clear.preference(key: NativeArtworkCopyPlacementKey.self,
                value: [artworkLayoutScope: geometry.frame(in: .named(artworkLayoutScope)).minY > 0.5])
            }
            if usesArtworkOverlay {
              // Keep the photograph visible between the top label and bottom copy.
              LinearGradient(stops: [
                .init(color: .black.opacity(0.50), location: 0),
                .init(color: .black.opacity(0.46), location: 0.20),
                .init(color: .black.opacity(0.12), location: 0.45),
                .init(color: .black.opacity(0.56), location: 0.78),
                .init(color: .black.opacity(0.60), location: 1),
              ], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
            }
          }
        }
        .coordinateSpace(name: artworkLayoutScope)
        .onPreferenceChange(NativeArtworkCopyPlacementKey.self) { values in
          if let below = values[artworkLayoutScope], below != copyBelowArtwork { copyBelowArtwork = below }
        }
        .background(usesArtworkOverlay ? Color.black : hasLoadedArtwork ? context.theme.foreground : context.theme.sunk)
      } else {
        copy
      }
  }
  @ViewBuilder private var contextTitle: some View {
    if artworkSource != nil, case .element(let title) = context.value("title"), title.typeName == "Tag" {
      context.slot("title")
        .environment(\.openUIArtworkTag, usesArtworkOverlay)
        .environment(\.openUITheme, context.theme)
        .environment(\.colorScheme, colorScheme)
    } else {
      context.slot("title").openUIFont(context.theme.textBodyDefaultHeavy, role: .title)
    }
  }
  private var copy: some View {
    VStack(alignment: centeredOverview ? .center : .leading,
      spacing: ["Overview", "Context"].contains(kind) ? context.theme.spaceS : context.theme.spaceM) {
      switch kind {
      case "Snippet":
        HStack(alignment: .center, spacing: context.theme.spacing("s")) {
          NativeLabelValueLayout(
            gap: context.theme.spaceM, minimumLabelWidth: context.presentation.minimumCompactCardWidth,
            allowsStacking: snippetValueNeedsUnbrokenWidth, centerVertically: true
          ) {
            context.slot("lhs")
            context.slot("rhs")
          }
          actionIndicator
        }
      case "Overview":
        HStack(alignment: .top, spacing: context.theme.spacing("s")) {
          context.slot("top").multilineTextAlignment(centeredOverview ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: copyAlignment)
          if isAction {
            Spacer(minLength: 0)
            actionIndicator
          }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        context.slot("bottom").multilineTextAlignment(centeredOverview ? .center : .leading)
          .frame(maxWidth: .infinity, alignment: copyAlignment)
          .alignmentGuide(.nativeOverviewMetricTop) { _ in 0 }
      case "Context":
        contextTitle
        if artworkSource != nil { Spacer(minLength: context.theme.spaceM) }
        if let body = context.string("body") {
          NativeMarkdownText(text: body, mode: .inline, style: contentTheme.textStyle(.compactBody).richText())
        }
      case "Visual":
        context.slot("tag")
          .environment(\.openUIArtworkTag, usesArtworkOverlay)
          .environment(\.openUITheme, context.theme)
          .environment(\.colorScheme, colorScheme)
        if artworkSource != nil { Spacer(minLength: context.theme.spaceM) }
        HStack(alignment: .center, spacing: context.theme.spacing("s")) {
          context.slot("body")
          if isAction {
            Spacer(minLength: 0)
            actionIndicator
          }
        }
      default:
        context.slot("header").environment(\.openUICardMediaInset, contentInset)
        context.slot("body")
        if let footer = context.value("footer"), footer != .null {
          NativeCompositeFooter(context: context, footer: footer)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
      }
      groupEntry
    }
      .environment(\.openUICardGroupAction, nil)
      .environment(\.openUICardMediaInset, 0)
      .padding(contentInset)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: centeredOverview ? .top : .topLeading)
  }
  @ViewBuilder private var groupEntry: some View {
    if let groupAction {
      // A sibling of content/links, inside this item's single surface.
      OpenUIActionSurface(context: context, message: groupAction.message, action: groupAction.action) {
        HStack(spacing: context.theme.spacing("s")) {
          Text(groupAction.message).multilineTextAlignment(.leading)
          Spacer(minLength: 0)
          Image(systemName: "chevron.right").accessibilityHidden(true)
        }
        .openUIFont(context.theme.textLabelSmHeavy, role: .control)
        .foregroundStyle(contentTheme.textNeutralPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .disabled(!context.canDispatch(groupAction.action))
      .accessibilityIdentifier("openui.card-item.group-action")
    }
  }
}

struct NativeCompositeFooter: View {
  let context: OpenUIComponentContext
  let footer: Value
  var body: some View {
    // An object footer balances amount and action when their complete widths
    // fit. It becomes a column before compressing either reading value. The
    // same mounted action survives that placement change.
    OpenUIFlexLayout(direction: "row", gap: context.theme.componentStyle.footerGap,
      align: "center", justify: "between", wrap: true) {
      context.render(NativeValue.prop(footer, "price") ?? .null)
      context.render(NativeValue.prop(footer, "button") ?? .null)
    }
  }
}

struct NativeCardBlock: View {
  let context: OpenUIComponentContext
  let kind: String
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .body) private var readingScale: CGFloat = 1
  @State private var selectedID = ""
  private var children: [OpenUIRenderChild] {
    var occurrences: [String: Int] = [:]
    return context.children("items").map { child in
      guard case .element(let item) = child.value, let statement = item.statementId else { return child }
      let ordinal = occurrences[statement, default: 0]; occurrences[statement] = ordinal + 1
      return OpenUIRenderChild(id: "statement:\(statement):\(ordinal)", value: child.value)
    }
  }
  private var layoutCount: Int? {
    let source = context.element.sourceReadiness["items"]
    return !source.complete && source.closed ? source.expectedCount : nil
  }
  private func selection(_ children: [OpenUIRenderChild]) -> Binding<String> {
    Binding(get: { children.contains(where: { $0.id == selectedID }) ? selectedID : children.first?.id ?? "" },
      set: { selectedID = $0 })
  }
  private var gap: CGFloat {
    CGFloat(
      min(
        128, max(0, context.presentationNumber("gap") ?? Double(context.theme.spacing(context.presentationString("gap"))))))
  }
  private func grid(_ children: [OpenUIRenderChild]) -> NativeCardGrid? {
    let layout = context.string("layout")
    // The standard component host admits only a committed layout. No guessed
    // carousel is needed while positional collection arguments are arriving.
    guard layout != "carousel" else { return nil }
    return NativeCardGrid(maxPerRow: ["Overview", "Context", "Visual"].contains(kind) ? 3 : 2,
      responsive: context.flag("responsive") != false,
      singleColumn: typeSize.isAccessibilitySize,
      minimumColumnWidth: (kind == "Overview" ? overviewMinimumWidth(children) : context.presentation.minimumCardWidth) * readingScale,
      spacing: gap)
  }
  private func overviewMinimumWidth(_ children: [OpenUIRenderChild]) -> CGFloat {
    // Horizontal media needs a real reading column next to the thumbnail;
    // compact text/icon metrics can share the row. This follows declared
    // component/layout roles, never the wording or length of a particular case.
    let hasHorizontalMedia = children.contains { child in
      guard case .element(let top) = NativeValue.prop(child.value, "top") else { return false }
      return top.typeName == "ImageText" && PropValue.string(top, "layout") != "vertical"
    }
    return hasHorizontalMedia ? context.presentation.minimumCardWidth : context.presentation.minimumCompactCardWidth
  }
  var body: some View {
    let children = self.children
    let byID = Dictionary(children.enumerated().map { ($0.element.id, $0.offset) },
      uniquingKeysWith: { first, _ in first })
    return Group {
      if children.isEmpty {
        EmptyView()
      } else {
        NativePager(ids: children.map(\.id), selection: selection(children), enabled: true,
          identifier: "openui.card-block.\(kind.lowercased())",
          showsControls: false,
          maximumPageWidth: context.presentation.maximumCarouselCardWidth,
          trailingPeek: context.presentation.carouselPeek, pageSpacing: gap, grid: grid(children), layoutCount: layoutCount, supportsAdjustment: false) { id in
          if let index = byID[id] {
            item(children[index], index: index)
          }
        }
      }
    }
  }
  private func item(_ item: OpenUIRenderChild, index: Int) -> some View {
    renderedItem(item, index: index)
      // Layout values belong on the pager's direct child. A value attached to
      // the card inside the dynamic renderer can be consumed by an intervening
      // layout before NativePagerLayout gets to read it.
      .layoutValue(key: NativeOverviewMetricKey.self,
        value: kind == "Overview" && NativeValue.prop(item.value, "bottom") != nil
          && NativeValue.prop(item.value, "bottom") != .null)
  }
  @ViewBuilder private func renderedItem(_ item: OpenUIRenderChild, index: Int) -> some View {
    if let value = context.value("action"), value != .null {
      let message = NativeCardAction.label(item.value, kind: kind, index: index)
      let action = NativeCardAction.action(value, item: item.value, kind: kind, index: index)
      if ["Snippet", "Overview", "Visual"].contains(kind) {
        // These upstream item types contain presentation-only slots.
        // The image and text share one native Button hit target.
        OpenUIActionSurface(context: context, message: message, action: action) {
          context.render(item.value).environment(\.openUICardIsAction, true)
        }.accessibilityLabel(message)
      } else {
        if case .element = item.value {
          context.render(item.value).environment(\.openUICardGroupAction,
            NativeCardGroupAction(message: message, action: action))
        } else {
          context.render(item.value)
        }
      }
    } else {
      context.render(item.value)
    }
  }
}
