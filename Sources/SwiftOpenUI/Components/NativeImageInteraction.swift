import SwiftLang
import SwiftUI

/// A tap never competes with a reading drag. Action cards retain their primary
/// tap; their images expose preview through the native touch-and-hold menu.
struct NativeImageInteraction: ViewModifier {
  let source: String?
  let image: Image?
  let alt: String
  var enabled = true
  var previewEnabled = true
  var failed = false
  var previewTheme: OpenUIThemeValues? = nil
  var previewAttempt = 0
  let retry: () -> Void
  @Environment(\.openUITheme) private var theme
  @Environment(\.isEnabled) private var hostEnabled
  @Environment(\.openUICardIsAction) private var cardIsAction
  @Environment(\.openUIMediaSourceReady) private var sourceReady
  @Environment(\.openUIMediaWidthReady) private var widthReady
  @Environment(\.openUIActivationIntent) private var intent
  @Environment(\.openUIResourceContext) private var resources
  @State private var preview = false
  @State private var previewResource: NativeMediaResourceTarget?

  private var ready: Bool { enabled && hostEnabled && sourceReady && widthReady }
  private var canPreview: Bool { ready && previewEnabled && image != nil }
  private var canTap: Bool { ready && (failed || (canPreview && !cardIsAction)) }
  private func activate() {
    guard canTap, intent?.permitsActivation != false else { return }
    if failed { retry() } else { openPreview() }
  }
  private func openPreview() {
    guard canPreview, intent?.permitsActivation != false else { return }
    previewResource = .init(source: source, resources: resources, attempt: previewAttempt)
    preview = true
  }
  func body(content: Content) -> some View {
    content
      .gesture(TapGesture().onEnded { activate() }, including: canTap && !failed ? .all : .subviews)
      .highPriorityGesture(TapGesture().onEnded { activate() }, including: canTap && failed ? .all : .subviews)
      .contextMenu {
        if canPreview {
          Button(action: openPreview) {
            Label { Text("View image", bundle: NativeControlResources.bundle) } icon: { Image(systemName: "photo") }
          }
        }
      }
      .accessibilityActions {
        if canTap {
          Button(action: activate) { Text(failed ? "Tap image to retry" : "View image", bundle: NativeControlResources.bundle) }
        } else if canPreview {
          Button(action: openPreview) { Text("View image", bundle: NativeControlResources.bundle) }
        }
      }
      .accessibilityHint(Text(canTap ? (failed ? "Tap image to retry" : "Tap to preview") : canPreview ? "Touch and hold to preview" : "", bundle: NativeControlResources.bundle))
      .sheet(isPresented: $preview) {
        NativeSingleImagePreview(source: source, image: image, imageTarget: previewResource, alt: alt, attempt: previewAttempt)
          .environment(\.openUITheme, previewTheme ?? theme)
      }
      .onChange(of: NativeMediaResourceTarget(source: source, resources: resources)) { _ in preview = false }
      .onChange(of: preview) { if !$0 { previewResource = nil } }
  }
}

struct NativeSingleImagePreview: View {
  let source: String?
  var image: Image? = nil
  var imageTarget: NativeMediaResourceTarget? = nil
  var alt = ""
  var attempt = 0
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openUITheme) private var theme
  @Environment(\.displayScale) private var displayScale
  @Environment(\.openUIResourceContext) private var resources
  @State private var zoomScale: CGFloat = 1
  var body: some View {
    VStack(spacing: theme.spaceM) {
      NativeImagePreviewHeader(closeIdentifier: "openui.image.preview.close", close: { dismiss() })
      GeometryReader { geometry in
        NativeRemoteImage(src: source, alt: alt, layout: .fit, role: .content,
          cachedImage: image, cachedImageTarget: imageTarget, upgradesCachedImage: true,
          requestedPixelSize: NativeMediaPreview.pixelSize(viewport: geometry.size,
            scale: displayScale, zoom: zoomScale, limits: resources.loader.resourceLimits),
          attempt: attempt, previewEnabled: false)
          .modifier(NativeImageZoom(scaleChanged: { zoomScale = $0 }))
      }
      NativeImagePreviewDescription(alt: alt)
    }
    .padding(theme.spaceML).frame(idealWidth: 720, idealHeight: 640)
    .foregroundStyle(theme.textNeutralPrimary)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("openui.image.preview")
  }
}

/// Preview copy stays complete without taking the image's entire viewport.
/// Both single-image and gallery readers use the same bounded reading region.
struct NativeImagePreviewDescription: View {
  let alt: String
  var details: String? = nil
  @Environment(\.openUITheme) private var theme
  @ScaledMetric(relativeTo: .body) private var readingScale: CGFloat = 1
  private var readableDetails: String? {
    guard let details, !details.isEmpty, details != alt else { return nil }
    return details
  }
  private var maximumHeight: CGFloat {
    let height = theme.textStyle(.body).font.measuredLineHeight(scale: readingScale) * 5
    return height.isFinite ? min(240, max(1, height)) : 120
  }

  var body: some View {
    if !alt.isEmpty || readableDetails != nil {
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: theme.spaceS) {
          if !alt.isEmpty {
            Text(alt).nativeTextStyle(theme.textStyle(.body))
              .fixedSize(horizontal: false, vertical: true)
          }
          if let details = readableDetails {
            Text(details).nativeTextStyle(theme.textStyle(.supporting))
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .lineLimit(nil)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: maximumHeight)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("openui.image.preview.description")
    }
  }
}

struct NativeImagePreviewHeader: View {
  var position: Int? = nil
  var count: Int = 1
  let closeIdentifier: String
  let close: () -> Void
  @Environment(\.openUITheme) private var theme
  var body: some View {
    HStack(spacing: theme.spaceM) {
      Text("Image preview", bundle: NativeControlResources.bundle).nativeTextStyle(theme.objectTitleStyle())
      Spacer(minLength: theme.spaceM)
      if let position, count > 1 {
        Text("\(position + 1) / \(count)").nativeTextStyle(theme.textStyle(.supporting)).monospacedDigit()
          .accessibilityIdentifier("openui.image.preview.position")
      }
      Button(action: close) { Image(systemName: "xmark").openUIControlTarget() }
        .buttonStyle(.plain).accessibilityLabel(Text("Close image preview", bundle: NativeControlResources.bundle))
        .keyboardShortcut(.cancelAction).accessibilityIdentifier(closeIdentifier)
    }
  }
}

struct NativeImageZoomState {
  var scale: CGFloat = 1
  var offset = CGSize.zero
  var isZoomed: Bool { scale > 1 }
  mutating func reset() { scale = 1; offset = .zero }
  mutating func setScale(_ proposed: CGFloat, size: CGSize) {
    scale = min(5, max(1, proposed))
    offset = bounded(offset, scale: scale, size: size)
  }
  func bounded(_ value: CGSize, scale: CGFloat, size: CGSize) -> CGSize {
    let x = max(0, size.width * (scale - 1) / 2), y = max(0, size.height * (scale - 1) / 2)
    return CGSize(width: min(x, max(-x, value.width)), height: min(y, max(-y, value.height)))
  }
}

struct NativeImageZoom: ViewModifier {
  var resetID: AnyHashable? = nil
  var zoomChanged: (Bool) -> Void = { _ in }
  var scaleChanged: (CGFloat) -> Void = { _ in }
  @State private var state = NativeImageZoomState()
  @GestureState private var magnification: CGFloat = 1
  @GestureState private var translation = CGSize.zero
  func body(content: Content) -> some View {
    GeometryReader { geometry in
      let zoom = min(5, max(1, state.scale * magnification))
      let position = state.bounded(CGSize(width: state.offset.width + translation.width, height: state.offset.height + translation.height), scale: zoom, size: geometry.size)
      content.scaleEffect(zoom).offset(position)
        .frame(width: geometry.size.width, height: geometry.size.height).clipped().contentShape(Rectangle())
        .gesture(MagnificationGesture().updating($magnification) { value, state, _ in state = value }
          .onEnded { value in
            state.setScale(state.scale * value, size: geometry.size)
          })
        .simultaneousGesture(DragGesture().updating($translation) { value, translation, _ in if state.isZoomed { translation = value.translation } }
          .onEnded { value in if state.isZoomed {
            state.offset = state.bounded(CGSize(width: state.offset.width + value.translation.width, height: state.offset.height + value.translation.height), scale: state.scale, size: geometry.size)
          } }, including: state.isZoomed ? .all : .subviews)
        .onTapGesture(count: 2) { if state.isZoomed { state.reset() } else { state.setScale(2, size: geometry.size) } }
        .onChange(of: state.isZoomed) { zoomChanged($0) }
        .onChange(of: state.scale) { scaleChanged($0) }
        .onChange(of: resetID) { _ in state.reset(); zoomChanged(false) }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("\(Int(state.scale * 100))%"))
        .accessibilityAdjustableAction { direction in
          switch direction {
          case .increment: state.setScale(state.scale + 1, size: geometry.size)
          case .decrement: state.setScale(state.scale - 1, size: geometry.size)
          @unknown default: break
          }
        }
        .accessibilityIdentifier("openui.image.preview.zoom")
    }
  }
}
