import SwiftLang
import SwiftUI

struct NativeModal: View {
  let context: OpenUIComponentContext
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var contentHeight: CGFloat = 420
  private var presented: Binding<Bool> {
    Binding(
      get: {
        if let binding = context.presentationBinding("open") {
          return binding.wrappedValue == .boolean(true) || binding.wrappedValue == .string("true")
        }
        let value = context.presentationFieldValue("open", fallback: context.value("open") ?? .undefined)
        return value == .boolean(true) || value == .string("true")
      },
      set: { open in
        guard context.isCurrentPresentation else { return }
        if let binding = context.presentationBinding("open") {
          binding.wrappedValue = .boolean(open)
        } else {
          context.setPresentationFieldValue("open", value: .boolean(open))
        }
      })
  }
  var body: some View {
    Color.clear.frame(width: 0, height: 0)
      .sheet(isPresented: presented) {
        VStack(alignment: .leading, spacing: context.theme.spacing("ml")) {
          HStack {
            Text(context.string("title") ?? "").openUIFont(context.theme.textBodyDefaultHeavy, role: .title).accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
              presented.wrappedValue = false
            } label: {
              Image(systemName: "xmark").openUIFont(context.theme.textLabelDefaultHeavy, role: .control).openUIControlTarget()
            }
            .buttonStyle(.plain).keyboardShortcut(.cancelAction)
            .accessibilityLabel(Text("Close", bundle: NativeControlResources.bundle))
          }
          .background(GeometryReader { geometry in
            Color.clear.preference(key: NativeModalSizes.self, value: [0: geometry.size.height])
          })
          ScrollView {
            context.slot().frame(maxWidth: .infinity, alignment: .leading)
              .fixedSize(horizontal: false, vertical: true)
              .background(GeometryReader { geometry in
                Color.clear.preference(key: NativeModalSizes.self, value: [1: geometry.size.height])
              })
          }
        }.padding(context.theme.spaceM).frame(
          idealWidth: context.string("size") == "lg"
            ? 720 : context.string("size") == "sm" ? 360 : 520, idealHeight: 420
        )
        .onPreferenceChange(NativeModalSizes.self) { parts in
          guard let header = parts[0], let body = parts[1] else { return }
          let height = header + body + context.theme.spaceML + context.theme.spaceM * 2
          if height.isFinite, height > 0, abs(height - contentHeight) > 0.5 { contentHeight = height }
        }
        .environment(\.dynamicTypeSize, typeSize)
        #if os(iOS)
        .presentationDetents(context.string("size") == "lg" ? [.large] : [
          .height(min(420, max(context.presentation.minimumControlTargetSize * 2, contentHeight))), .large
        ])
        .presentationDragIndicator(.visible)
        #endif
      }
  }
}

private struct NativeModalSizes: PreferenceKey {
  static let defaultValue: [Int: CGFloat] = [:]
  static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
    value.merge(nextValue(), uniquingKeysWith: { _, next in next })
  }
}
