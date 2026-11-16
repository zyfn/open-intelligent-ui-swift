import SwiftLang
import SwiftUI

/// A read-only view over the same prepared data as the plot. No values are
/// inferred, truncated, or re-evaluated when the reader is opened.
struct NativeChartDataDetails: View {
  let data: NativeChartData
  let palette: [Color]
  let theme: OpenUIThemeValues
  let locale: Locale
  let selectedIndex: Int?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    let count = data.inspectionCount
    NavigationStack {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: theme.spaceS) {
            if count == 0 {
              Text("No data", bundle: NativeControlResources.bundle)
                .nativeTextStyle(theme.textStyle(.supporting))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(0..<count, id: \.self) { index in
              if let details = data.inspection(at: index, locale: locale) {
                NativeChartInspectionContent(details: details, palette: palette, theme: theme)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .id(index)
                  .accessibilityIdentifier("openui.chart.data.\(index)")
                if index + 1 < count { Divider().accessibilityHidden(true) }
              }
            }
          }.padding(theme.spaceM)
        }
        .onAppear {
          if let selectedIndex, (0..<count).contains(selectedIndex) {
            proxy.scrollTo(selectedIndex, anchor: .top)
          }
        }
      }
      .background(theme.background)
      .navigationTitle(Text("Chart data", bundle: NativeControlResources.bundle))
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button { dismiss() } label: { Text("Done", bundle: NativeControlResources.bundle) }
        }
      }
    }
    #if os(macOS)
    .frame(minWidth: 320, idealWidth: 520, maxWidth: 760,
      minHeight: 280, idealHeight: 520, maxHeight: 800)
    #endif
  }
}
