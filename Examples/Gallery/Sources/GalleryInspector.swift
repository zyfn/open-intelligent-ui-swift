import SwiftUI
import SwiftLang

@MainActor struct GallerySourceEditor: View {
    @ObservedObject var session: GalleryDocumentSession
    var component: GalleryComponent? = nil
    @State private var showsComponentUsage = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("OpenUI Lang").font(.headline)
                Spacer()
                ShareLink(item: session.draft) { Label("导出源码", systemImage: "square.and.arrow.up") }
                    .labelStyle(.iconOnly)
                    .help("导出源码")
            }
            .padding(16)
            Divider()
            if let component {
                DisclosureGroup("组件用法", isExpanded: $showsComponentUsage) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(component.definition.signature)
                                .font(.system(.caption, design: .monospaced))
                            Text(component.definition.description)
                                .font(.callout).foregroundStyle(.secondary)
                            if component.supporting {
                                Text(component.container.map { "在 \($0) 中展示 \(component.name) 的实际用法。" }
                                     ?? "这是数据定义。参数和用法见下方源码。")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                    }
                    .frame(maxHeight: 180)
                }
                .font(.subheadline.weight(.medium))
                .padding(16)
                Divider()
            }
            TextEditor(text: $session.draft)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .disabled(session.playback == .streaming || session.playback == .paused)
                .scrollContentBackground(.hidden)
                .padding(12)
                .accessibilityLabel("OpenUI Lang 源码")
            Divider()
            HStack(spacing: 12) {
                Button("应用源码") { session.render() }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.playback == .streaming)
                Button("恢复原稿") { session.restore() }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .background(.background)
        .frame(minWidth: 280, idealWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor struct GalleryPlaybackControls: View {
    @ObservedObject var session: GalleryDocumentSession

    var body: some View {
        let primary = primaryPresentation
        return Menu {
            Section(session.playback.rawValue) {
                Button(action: performPrimaryAction) {
                    Label(primary.title, systemImage: primary.symbol)
                }
                if session.playback == .streaming || session.playback == .paused {
                    Button("从头播放") { session.stream() }
                }
                Button { session.interrupt() } label: { Label("中断", systemImage: "stop") }
                    .disabled(session.playback != .streaming && session.playback != .paused)
                Button("完整渲染") { session.render() }
            }
        } label: {
            Label(primary.title, systemImage: primary.symbol).labelStyle(.iconOnly)
        } primaryAction: {
            performPrimaryAction()
        }
        .accessibilityLabel(primary.title)
        .accessibilityValue(session.playback.rawValue)
        .help("\(session.playback.rawValue) · \(primary.title)")
    }

    private var primaryPresentation: (title: String, symbol: String) {
        if session.pendingSuffix != nil { return ("追加流式后缀", "play") }
        switch session.playback {
        case .streaming: return ("暂停", "pause")
        case .paused: return ("继续", "play")
        default: return ("流式播放", "play")
        }
    }

    private func performPrimaryAction() {
        if session.pendingSuffix != nil {
            session.appendSuffix()
        } else if session.playback == .streaming {
            session.pause()
        } else if session.playback == .paused {
            session.resume()
        } else {
            session.stream()
        }
    }
}
