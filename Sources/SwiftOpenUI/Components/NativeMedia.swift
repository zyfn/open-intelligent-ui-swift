import Foundation
import ImageIO
import SwiftLang
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum NativeMediaStatus: Equatable { case loading, loaded, unavailable }
enum NativeMediaLayout {
  case cover, aspect(CGFloat), thumbnail(CGSize), fit, fill, intrinsic
}
/// Content images retain a quiet surface; compact artwork uses its owner's
/// surface. The layout determines geometry in every resource state.
enum NativeMediaRole: Equatable { case artwork, content }

/// A resource placeholder is not an alert. Ordinary images show a short status
/// only when it fits; owner-provided symbols retain their compact appearance.
struct NativeUnavailableMedia: View {
  let theme: OpenUIThemeValues
  var systemImage: String? = nil
  @ScaledMetric(relativeTo: .body) private var glyphSize: CGFloat = 16
  @ScaledMetric(relativeTo: .body) private var semanticGlyphSize: CGFloat = 24

  var body: some View {
    GeometryReader { geometry in
      let available = max(0, min(geometry.size.width, geometry.size.height))
      if let systemImage {
        Image(systemName: systemImage)
          .font(.system(size: min(semanticGlyphSize, available * 0.42), weight: .medium))
          .foregroundStyle(theme.interactiveAccentDefault)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        let side = min(glyphSize, available)
        ViewThatFits(in: [.horizontal, .vertical]) {
          if geometry.size.width >= 160 {
            VStack(spacing: theme.spaceXs) {
              glyph(side)
              Text("Image unavailable", bundle: NativeControlResources.bundle)
                .nativeTextStyle(theme.textStyle(.supporting))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, theme.spaceS)
            }.fixedSize()
          }
          glyph(side)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .accessibilityHidden(true).allowsHitTesting(false)
  }

  private func glyph(_ side: CGFloat) -> some View {
    Image(systemName: "photo").resizable().scaledToFit()
      .frame(width: side, height: side).foregroundStyle(theme.textNeutralSecondary)
  }
}

private struct NativeMediaTaskID: Hashable {
  let target: NativeMediaResourceTarget?
  let sourceReady: Bool
  let pixelSize: Int
  let displaySize: NativeImageDisplaySize?
  let sizeReady: Bool
  let cache: ObjectIdentifier?
  let generation: Int?
  let visible: Bool
}
/// Shared native resource presentation. Resource states preserve the declared
/// media layout; network failures remain separate from language diagnostics.
struct NativeRemoteImage: View {
    @Environment(\.openUIPresentation) private var nativePresentation
    @Environment(\.displayScale) private var displayScale

  let src: String?
  var alt = ""
  var layout: NativeMediaLayout = .cover
  var role: NativeMediaRole = .artwork
  var fallbackSystemImage: String? = nil
  var cachedImage: Image?
  var cachedImageTarget: NativeMediaResourceTarget? = nil
  // A preview can show its inline image immediately while loading the pixels
  // needed by the larger viewport. Supplied fixture images remain authoritative.
  var upgradesCachedImage = false
  var requestedPixelSize: Int? = nil
  var releasesImageWhenHidden = false
  var attempt = 0
  var onStatus: ((NativeMediaStatus, Image?) -> Void)?
  var onResource: ((NativeMediaCache.Entry) -> Void)?
  var interactionEnabled = true
  var previewEnabled = true
  @State private var localRetry = NativeImageRetryState()
  @Environment(\.openUIMediaSourceReady) private var sourceReady
  @Environment(\.openUIStreamActive) private var streamActive
  @Environment(\.openUIMediaWidthReady) private var widthReady
  @State private var phase: AsyncImagePhase = .empty
  @State private var loadedEntry: NativeMediaCache.Entry?
  @State private var loadedRequest: NativeResourceRequestID?
  @State private var requestSnapshot: NativeMediaRequestSnapshot?
  @State private var revealLoadedImage = true
  @State private var visible = false
  @State private var measuredDisplaySize: NativeImageDisplaySize?
  @Environment(\.openUIResourceContext) private var resources
  @Environment(\.openUITheme) private var theme
  @Environment(\.openUIMediaCache) private var mediaCache

  var body: some View {
    ZStack {
      // Each media role owns its frame before pixels arrive. A later parent
      // layout argument must not temporarily replace it with a small thumbnail.
      if !widthReady && needsResolvedWidth {
        NativePendingContent(loading: streamActive, message: "Loading image")
      } else if let presentation = presentedImage {
        picture(presentation.image, retainedSize: presentation.size, reveal: presentation.reveal)
          .onAppear { didPresent(presentation.image) }
          .onChange(of: requestID) { _ in
            didPresent(presentation.image)
          }
          .onChange(of: presentation.pixelSize) { _ in didPresent(presentation.image) }
      } else {
        // Resource states share one canvas so a failure never changes the
        // reserved image geometry or moves its neighboring content.
        placeholder(loading: waitingForImage)
          .onAppear(perform: reportPlaceholder)
          .onChange(of: waitingForImage) { _ in reportPlaceholder() }
          .onChange(of: requestID) { _ in reportPlaceholder() }
      }
    }
    // Measurement belongs to the mounted image, not to either resource phase.
    // A loading canvas retiring while its replacement appears must not write
    // an old viewport over a newer width received by the same mounted image.
    .background {
      GeometryReader { geometry in
        let target: NativeImageDisplaySize? = widthReady && requestedPixelSize == nil && needsResolvedWidth
          ? NativeMediaPreview.displaySize(viewport: geometry.size, scale: displayScale, mode: displayMode)
          : nil
        Color.clear
          .onAppear { recordDisplaySize(target) }
          .onChange(of: target) { recordDisplaySize($0) }
      }
    }
    .modifier(NativeImageInteraction(source: src, image: displayedImage, alt: alt,
      enabled: interactionEnabled,
      previewEnabled: previewEnabled, failed: failed, isImageSurface: true,
      previewAttempt: resourceTarget.attempt,
      retry: { localRetry.retry(baseTarget) }))
    .task(id: NativeMediaTaskID(target: sourceReady ? resourceTarget : nil,
      sourceReady: sourceReady, pixelSize: targetPixelSize,
      displaySize: targetDisplaySize, sizeReady: decodeSizeReady,
      cache: mediaCache.map(ObjectIdentifier.init), generation: mediaCache?.generation,
      visible: !releasesImageWhenHidden || visible)) {
      guard sourceReady, decodeSizeReady, !releasesImageWhenHidden || visible,
        validCachedImage == nil || upgradesCachedImage, !Task.isCancelled else { return }
      let snapshot: NativeMediaRequestSnapshot
      if let current = requestSnapshot, current.matches(resourceTarget, cache: mediaCache) {
        snapshot = current
      } else {
        snapshot = NativeMediaRequestSnapshot(target: resourceTarget, cache: mediaCache)
        requestSnapshot = snapshot
      }
      guard snapshot.target.isCurrent else { return }
      if loadedRequest == snapshot.request, let loadedEntry = currentLoadedEntry,
        loadedEntry.satisfies(targetPixelSize, displaySize: targetDisplaySize) {
        return
      }
      if let retained = mediaCache?[snapshot.request],
        retained.satisfies(targetPixelSize, displaySize: targetDisplaySize) {
        // A mounted image owns its successful phase. The bounded presentation
        // cache can evict this entry while later cards are still arriving.
        accept(retained, for: snapshot.request)
        revealLoadedImage = !retained.wasPresented
        return
      }
      if snapshot.request.request == nil { onStatus?(.unavailable, nil) } else { await load(snapshot) }
    }
    .onAppear { visible = true }
    .onDisappear {
      visible = false
      if releasesImageWhenHidden {
        loadedEntry = nil; phase = .empty; loadedRequest = nil
      }
    }
  }
  private var presentedImage: (image: Image, size: CGSize?, reveal: Bool, pixelSize: Int?)? {
    guard sourceReady, !releasesImageWhenHidden || visible else { return nil }
    let cachedImage = validCachedImage
    if let cachedImage, !upgradesCachedImage { return (cachedImage, nil, false, nil) }
    guard let requestID else { return cachedImage.map { ($0, nil, false, nil) } }
    if loadedRequest == requestID, let loadedEntry = currentLoadedEntry {
      return (loadedEntry.image, loadedEntry.size, revealLoadedImage, loadedEntry.decodedPixelSize)
    }
    if loadedRequest != requestID, let retained = mediaCache?[requestID] {
      return (retained.image, retained.size, !retained.wasPresented, retained.decodedPixelSize)
    }
    return cachedImage.map { ($0, nil, false, nil) }
  }
  private var validCachedImage: Image? {
    if let target = cachedImageTarget, (!target.isCurrent || target != baseTarget) { return nil }
    return cachedImage
  }
  private var waitingForImage: Bool {
    if releasesImageWhenHidden && !visible { return false }
    if !sourceReady { return streamActive }
    guard resourceTarget.isCurrent else { return false }
    // The task resolves a new target once. A cache hit restores its successful
    // phase before we announce loading to the containing card or gallery.
    guard let requestID else { return src != nil }
    return requestID.request != nil && !failed
  }
  private var displayedImage: Image? {
    presentedImage?.image
  }
  // A host can tighten its resource policy without changing the URL. Mounted
  // pixels have the same policy boundary as the shared completed-image cache.
  private var currentLoadedEntry: NativeMediaCache.Entry? {
    guard let loadedEntry, loadedEntry.resourceLimits == resources.loader.resourceLimits else { return nil }
    return loadedEntry
  }
  private var failed: Bool {
    guard sourceReady, let requestID, requestID.request != nil, loadedRequest == requestID else { return false }
    if case .failure = phase { return true }; return false
  }
  private var baseTarget: NativeMediaResourceTarget {
    .init(source: src, resources: resources, attempt: attempt)
  }
  private var resourceTarget: NativeMediaResourceTarget {
    .init(source: src, resources: resources, attempt: attempt + localRetry.attempt(for: baseTarget))
  }
  private var requestID: NativeResourceRequestID? {
    if let snapshot = requestSnapshot, snapshot.matches(resourceTarget, cache: mediaCache) { return snapshot.request }
    return resourceTarget.cachedRequest(in: mediaCache)
  }
  private func didPresent(_ image: Image) {
    guard sourceReady, resourceTarget.isCurrent else { return }
    if let requestID { mediaCache?.markPresented(requestID) }
    onStatus?(.loaded, image)
  }
  private func reportPlaceholder() {
    guard presentedImage == nil, !sourceReady || requestID != nil || src == nil else { return }
    onStatus?(waitingForImage ? .loading : .unavailable, nil)
  }
  private var targetPixelSize: Int {
    NativeMediaCache.effectivePixelSize(requestedPixelSize, limits: resources.loader.resourceLimits)
  }
  private var displayMode: NativeImageDisplaySize.Mode {
    switch layout {
    case .intrinsic: return .width
    case .fit: return .fit
    default: return .fill
    }
  }
  private var targetDisplaySize: NativeImageDisplaySize? {
    if requestedPixelSize != nil { return nil }
    if case .thumbnail(let size) = layout {
      return NativeMediaPreview.displaySize(viewport: size, scale: displayScale, mode: .fill)
    }
    guard widthReady, measuredDisplaySize?.mode == displayMode else { return nil }
    return measuredDisplaySize
  }
  private var decodeSizeReady: Bool {
    requestedPixelSize != nil || targetDisplaySize != nil
  }
  private func recordDisplaySize(_ target: NativeImageDisplaySize?) {
    if measuredDisplaySize != target { measuredDisplaySize = target }
  }
  private var needsResolvedWidth: Bool {
    if case .thumbnail = layout { return false }
    return true
  }
  @MainActor private func load(_ snapshot: NativeMediaRequestSnapshot) async {
    let id = snapshot.request
    let generation = mediaCache?.generation
    guard let request = id.request else { return }
    // A size upgrade keeps the last accepted pixels. A different resource may
    // never borrow them, including across authorization or retry boundaries.
    if loadedRequest != id || currentLoadedEntry == nil {
      loadedEntry = mediaCache?[id]; revealLoadedImage = loadedEntry == nil
    }
    loadedRequest = id; phase = .empty
    do {
      let entry: NativeMediaCache.Entry
      if let mediaCache {
        entry = try await mediaCache.resource(id, loader: snapshot.target.loader,
          targetPixelSize: targetPixelSize, displaySize: targetDisplaySize)
      } else {
        entry = try await NativeMediaCache.load(request, loader: snapshot.target.loader,
          targetPixelSize: targetPixelSize, displaySize: targetDisplaySize)
      }
      try Task.checkCancellation()
      guard !releasesImageWhenHidden || visible,
            snapshot.matches(resourceTarget, cache: mediaCache), id == requestID,
            mediaCache?.generation == generation else { return }
      accept(entry, for: id)
    } catch {
      guard !Task.isCancelled, snapshot.matches(resourceTarget, cache: mediaCache),
            id == requestID, mediaCache?.generation == generation else { return }
      phase = .failure(error)
    }
  }
  @MainActor private func accept(_ entry: NativeMediaCache.Entry, for id: NativeResourceRequestID) {
    if loadedRequest != id || currentLoadedEntry.map({ $0.decodedPixelSize < entry.decodedPixelSize }) != false {
      loadedEntry = entry
    }
    loadedRequest = id
    if let loadedEntry = currentLoadedEntry {
      phase = .success(loadedEntry.image)
      onResource?(loadedEntry)
    }
  }
  private func picture(_ image: Image, retainedSize: CGSize? = nil, reveal: Bool = true) -> some View {
    let mode: ContentMode
    switch layout {
    case .intrinsic, .fit: mode = .fit
    default: mode = .fill
    }
    return canvas(sourceSize: retainedSize) {
      image.resizable().aspectRatio(contentMode: mode)
        .modifier(NativeMediaReveal(enabled: reveal, fallbackSystemImage: fallbackSystemImage))
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(alt.isEmpty ? Text("View image", bundle: NativeControlResources.bundle) : Text(alt))
    .accessibilityAddTraits(.isImage).accessibilityHidden(alt.isEmpty && !interactionEnabled)
  }
  private func placeholder(loading: Bool) -> some View {
    canvas {
      ZStack {
        if role == .content && fallbackSystemImage == nil {
          loading ? theme.imagePlaceholderBackground : theme.sunk
        }
        // Failure copy must not sit beneath a translucent loading surface.
        // Swap states without cross-fading their separate photo symbols.
        if loading && fallbackSystemImage == nil {
          NativeLoadingSurface(showsMediaSymbol: true, background: theme.imagePlaceholderBackground)
            .transition(.identity)
        } else {
          NativeUnavailableMedia(theme: theme, systemImage: fallbackSystemImage)
            .transition(.identity)
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(alt.isEmpty
      ? Text(loading ? "Loading image" : "Image unavailable", bundle: NativeControlResources.bundle)
      : Text(alt))
    .accessibilityValue(Text(alt.isEmpty ? "" : loading ? "Loading image" : "Image unavailable",
      bundle: NativeControlResources.bundle))
    .accessibilityAddTraits(.isImage)
    .accessibilityIdentifier(loading ? "openui.media.loading" : "openui.media.unavailable")
  }
  // Document illustrations retain their source proportions; photo previews
  // use the same declared role in every resource state.
  @ViewBuilder private func canvas<Content: View>(sourceSize: CGSize? = nil,
    @ViewBuilder _ content: () -> Content) -> some View {
    let surface = Color.clear.overlay { content().accessibilityHidden(true) }.clipped().contentShape(Rectangle())
    switch layout {
    case .cover:
      surface.aspectRatio(nativePresentation.coverAspectRatio, contentMode: .fit).fixedSize(horizontal: false, vertical: true)
    case .aspect(let ratio):
      surface.aspectRatio(ratio, contentMode: .fit).fixedSize(horizontal: false, vertical: true)
    case .thumbnail(let size): surface.frame(width: size.width, height: size.height)
    case .fit, .fill: surface.frame(maxWidth: .infinity, maxHeight: .infinity)
    case .intrinsic:
      // Only the currently presented resource supplies its dimensions. A new
      // source or failure must not inherit the previous image's proportions.
      surface.aspectRatio(NativeMediaPreview.aspectRatio(sourceSize: sourceSize), contentMode: .fit)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct NativeGalleryResourceID: Hashable {
  let itemID: String
  let target: NativeMediaResourceTarget
}

private struct NativeGalleryImage: Identifiable {
  let id: String
  let index: Int
  let src: String?
  let alt: String
  let details: String?
  let target: NativeMediaResourceTarget
  let sourceReady: Bool
  var key: NativeGalleryResourceID { .init(itemID: id, target: target) }

  func retargeted(resources: OpenUIResourceContext, attempt: Int) -> Self {
    .init(id: id, index: index, src: src, alt: alt, details: details,
      target: .init(source: src, resources: resources, attempt: attempt), sourceReady: sourceReady)
  }
}

/// Small galleries are measured synchronously at their actual container width.
/// Columns never outnumber the supplied images, so sparse galleries fill the row.
struct NativeGalleryGridLayout: Layout {
  let minimumWidth: CGFloat
  let gap: CGFloat
  var maximumColumns: Int?
  var layoutCount: Int? = nil

  private func frames(_ proposal: ProposedViewSize, _ subviews: Subviews) -> (CGFloat, [CGRect]) {
    let width = proposal.width.flatMap { $0.isFinite ? max(1, $0) : nil } ?? max(1, minimumWidth)
    guard !subviews.isEmpty else { return (width, []) }
    let count = max(subviews.count, layoutCount ?? subviews.count)
    let columns = min(count, maximumColumns ?? count,
      max(1, Int((width + gap) / max(1, minimumWidth + gap))))
    let tileWidth = max(1, (width - gap * CGFloat(columns - 1)) / CGFloat(columns))
    let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: tileWidth, height: nil)) }
    var result: [CGRect] = []
    var y: CGFloat = 0
    for start in stride(from: 0, to: subviews.count, by: columns) {
      let end = min(start + columns, subviews.count)
      let rowHeight = sizes[start..<end].map(\.height).max() ?? 0
      for index in start..<end {
        result.append(CGRect(x: CGFloat(index - start) * (tileWidth + gap), y: y,
          width: tileWidth, height: sizes[index].height))
      }
      y += rowHeight + gap
    }
    return (width, result)
  }
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let (width, frames) = frames(proposal, subviews)
    return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let (_, frames) = frames(ProposedViewSize(width: bounds.width, height: nil), subviews)
    for (view, frame) in zip(subviews, frames) {
      view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
        anchor: .topLeading, proposal: ProposedViewSize(width: frame.width, height: nil))
    }
  }
}

struct NativeImageGallery: View {
  let context: OpenUIComponentContext
  @Environment(\.openUIResourceContext) private var resources
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .body) private var readingScale: CGFloat = 1
  @State private var phases: [NativeGalleryResourceID: NativeMediaStatus] = [:]
  @State private var selected: NativeGalleryResourceID?
  @State private var preview = false
  @State private var retries: [String: Int] = [:]
  // Keep the inline preview compact; opening a photo presents the full gallery.
  private let previewLimit = 5
  @State private var stableImages: [NativeGalleryImage]?
  private var images: [NativeGalleryImage] {
    if context.hasPendingData || context.hasDataFailure, let stableImages {
      // Keep the readable data during a query refresh, but never carry pixels
      // from a previous loader/account into the new resource environment.
      return stableImages.map { $0.retargeted(resources: resources, attempt: retries[$0.id, default: 0]) }
    }
    return currentImages
  }
  private var currentImages: [NativeGalleryImage] {
    let children = context.presentationChildren("images")
    let source = context.element.sourceReadiness["images"]
    let mapped = source.valueIndices.map { $0.compactMap { $0 } == Array(children.indices) } ?? false
    let aligned = source.complete || source.expectedCount == children.count || mapped
    return children.enumerated().map { index, child in
      let attempt = retries[child.id, default: 0]
      let src = NativeValue.string(child.value, "src")
      return NativeGalleryImage(id: child.id, index: index,
        src: src, alt: NativeValue.string(child.value, "alt") ?? "",
        details: NativeValue.string(child.value, "details"),
        target: .init(source: src, resources: resources, attempt: attempt),
        sourceReady: {
          if case .element(let image) = child.value { return image.sourceReadiness["src"].complete }
          guard aligned else { return false }
          return source[index]["src"].complete
        }())
    }
  }
  private var visible: [NativeGalleryImage] { Array(images.prefix(previewLimit)) }
  private var gridReady: Bool {
    if stableImages != nil && (context.hasPendingData || context.hasDataFailure) { return true }
    return NativeLayoutContract.collectionShapeReady(context.element.sourceReadiness["images"], count: images.count)
  }
  private var layoutCount: Int? {
    let source = context.element.sourceReadiness["images"]
    return !source.complete && source.closed ? source.expectedCount.map { min(previewLimit, $0) } : nil
  }
  private func rememberImages() {
    if gridReady && !context.hasPendingData && !context.hasDataFailure { stableImages = currentImages }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: context.theme.spaceM) {
      if !gridReady || (visible.isEmpty && (context.hasPendingData || (context.isStreaming && !context.element.isSourceComplete))) {
        NativePendingContent(loading: !context.hasDataFailure && (context.isStreaming || context.hasPendingData), message: "Loading image")
      } else if !visible.isEmpty {
        NativeGalleryGridLayout(minimumWidth: max(context.presentation.thumbnailSize,
            context.presentation.minimumCompactCardWidth * readingScale),
          gap: context.theme.spaceM, maximumColumns: typeSize.isAccessibilitySize ? 1 : nil, layoutCount: layoutCount) {
          ForEach(visible) { image in
            VStack(alignment: .leading, spacing: context.theme.spacing("xs")) {
              Button {
                guard context.canActivate else { return }
                if phases[image.key] == .unavailable { retry(image) }
                else { selected = image.key; preview = true }
              } label: {
                NativeRemoteImage(
                  src: image.src, alt: image.alt, layout: .cover,
                  attempt: image.target.attempt,
                  onStatus: { phase, _ in record(phase, for: image.key) }, interactionEnabled: false
                )
                .environment(\.openUIMediaSourceReady, image.sourceReady)
                .background(context.theme.sunk)
                .clipShape(RoundedRectangle(cornerRadius: context.theme.radiusM, style: .continuous))
              }
              .buttonStyle(.plain).disabled(!context.canInteract || (!image.sourceReady)
                || (phases[image.key] != .loaded && phases[image.key] != .unavailable))
              .accessibilityLabel(image.alt.isEmpty ? Text("View image", bundle: NativeControlResources.bundle) : Text(image.alt))
              .accessibilityValue(
                phases[image.key] == .unavailable
                  ? Text("Image unavailable", bundle: NativeControlResources.bundle)
                  : phases[image.key] != .loaded ? Text("Loading image", bundle: NativeControlResources.bundle) : Text("")
              )
              .accessibilityIdentifier("openui.gallery.image.\(image.index)")
              if let details = image.details { Text(details).nativeTextStyle(context.theme.textStyle(.supporting)) }
            }
          }
        }
      }
    }
    .accessibilityElement(children: .contain).accessibilityIdentifier("openui.gallery")
    .onAppear(perform: rememberImages)
    .onChange(of: ObjectIdentifier(context.element)) { _ in rememberImages() }
    .onChange(of: context.hasPendingData) { _ in rememberImages() }
    .sheet(isPresented: $preview) {
      NativeGalleryPreview(images: images, selected: $selected, phases: phases, record: record, retry: retry)
    }
    .onChange(of: images.map(\.key)) { keys in
      let current = Set(keys)
      phases = phases.filter { current.contains($0.key) }
      let items = Set(keys.map(\.itemID))
      retries = retries.filter { items.contains($0.key) }
      if selected.map(current.contains) != true { preview = false; selected = nil }
    }
  }
  private func retry(_ image: NativeGalleryImage) {
    retries[image.id, default: 0] += 1
    if selected == image.key { selected = currentImages.first(where: { $0.id == image.id })?.key }
  }
  private func record(_ phase: NativeMediaStatus, for key: NativeGalleryResourceID) {
    guard key.target.isCurrent, images.contains(where: { $0.key == key }) else { return }
    if phases[key] != .loaded && phases[key] != phase { phases[key] = phase }
  }
}

private struct NativeGalleryPreview: View {
    @Environment(\.openUIPresentation) private var nativePresentation

  let images: [NativeGalleryImage]
  @Binding var selected: NativeGalleryResourceID?
  let phases: [NativeGalleryResourceID: NativeMediaStatus]
  let record: (NativeMediaStatus, NativeGalleryResourceID) -> Void
  let retry: (NativeGalleryImage) -> Void
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openUITheme) private var theme
  @State private var zoomed = false
  private var image: NativeGalleryImage? { images.first { $0.key == selected } }
  var body: some View {
    VStack(alignment: .leading, spacing: theme.spacing("m")) {
      NativeImagePreviewHeader(position: image?.index, count: images.count,
        closeIdentifier: "openui.gallery.close", close: { dismiss() })
      if let image {
        GeometryReader { geometry in
          NativePager(ids: images.map(\.key), selection: Binding(
            get: { selected ?? image.key }, set: { selected = $0; zoomed = false }),
            enabled: !zoomed, identifier: "openui.gallery.preview", supportsAdjustment: false, pageRadius: 1) { key in
            if let item = images.first(where: { $0.key == key }) {
              NativeGalleryPreviewPage(item: item, size: geometry.size, selection: selected,
                record: { record($0, item.key) }, zoomChanged: { value in
                  if selected == item.key { zoomed = value }
                })
            }
          }
        }.accessibilityIdentifier("openui.gallery.preview.image")
          .accessibilityHint(Text(zoomed ? "Drag to move image" : "Swipe to change image", bundle: NativeControlResources.bundle))
        NativeImagePreviewDescription(alt: image.alt, details: image.details)
      }
      ScrollViewReader { reader in
        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(spacing: theme.spaceM) {
            ForEach(images) { image in
              Button { if phases[image.key] == .unavailable { retry(image) } else { selected = image.key; zoomed = false } } label: {
                NativeRemoteImage(src: image.src, alt: image.alt,
                  layout: .thumbnail(CGSize(width: nativePresentation.compactThumbnailSize,
                    height: nativePresentation.compactThumbnailSize / nativePresentation.coverAspectRatio)),
                  releasesImageWhenHidden: true, attempt: image.target.attempt,
                  onStatus: { phase, _ in record(phase, image.key) }, interactionEnabled: false)
                  .environment(\.openUIMediaSourceReady, image.sourceReady)
                  .clipShape(RoundedRectangle(cornerRadius: theme.radiusM, style: .continuous))
                  .overlay(RoundedRectangle(cornerRadius: theme.radiusM, style: .continuous).strokeBorder(selected == image.key ? theme.interactiveAccentDefault : .clear, lineWidth: 2))
              }.buttonStyle(.plain)
                .accessibilityLabel(image.alt.isEmpty ? Text("View image", bundle: NativeControlResources.bundle) : Text(image.alt))
                .accessibilityIdentifier("openui.gallery.thumbnail.\(image.index)")
                .id(image.key)
            }
          }
        }
        .frame(height: nativePresentation.compactThumbnailSize / nativePresentation.coverAspectRatio)
        .onAppear { if let selected { reader.scrollTo(selected, anchor: .center) } }
        .onChange(of: selected) { key in
          zoomed = false
          if let key { reader.scrollTo(key, anchor: .center) }
        }
      }
    }
    .padding(theme.spaceML).frame(idealWidth: 720, idealHeight: 640)
    .foregroundStyle(theme.textNeutralPrimary)
    .background(theme.background.ignoresSafeArea())
    .accessibilityElement(children: .contain).accessibilityIdentifier("openui.gallery.preview")
  }
}

/// Pixel ownership follows the pager's mounted neighbor window. No parent
/// dictionary pins every decoded page after the user has moved past it.
private struct NativeGalleryPreviewPage: View {
  let item: NativeGalleryImage
  let size: CGSize
  let selection: NativeGalleryResourceID?
  let record: (NativeMediaStatus) -> Void
  let zoomChanged: (Bool) -> Void
  @Environment(\.displayScale) private var displayScale
  @Environment(\.openUIResourceContext) private var resources
  @State private var zoomScale: CGFloat = 1

  var body: some View {
    NativeRemoteImage(src: item.src, alt: item.alt, layout: .fit, role: .content,
      requestedPixelSize: NativeMediaPreview.pixelSize(viewport: size, scale: displayScale,
        zoom: zoomScale, limits: resources.loader.resourceLimits),
      releasesImageWhenHidden: true, attempt: item.target.attempt,
      onStatus: { phase, _ in record(phase) }, previewEnabled: false)
      .environment(\.openUIMediaSourceReady, item.sourceReady)
      .modifier(NativeImageZoom(resetID: selection, zoomChanged: zoomChanged,
        scaleChanged: { zoomScale = $0 }))
      .frame(width: size.width, height: size.height)
  }
}

struct NativeImageRetryState {
  private var key: AnyHashable?
  private var count = 0
  func attempt(for request: AnyHashable) -> Int { key == request ? count : 0 }
  mutating func retry(_ request: AnyHashable) {
    if key != request { key = request; count = 0 }
    count += 1
  }
}

struct NativeImageBlock: View {
  let context: OpenUIComponentContext
  var body: some View {
    NativeRemoteImage(src: context.string("src"), alt: context.string("alt") ?? "",
      layout: .aspect(context.presentation.coverAspectRatio), role: .content)
      .clipShape(RoundedRectangle(cornerRadius: context.theme.radiusM, style: .continuous))
  }
}
