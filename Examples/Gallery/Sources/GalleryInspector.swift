import SwiftUI
import SwiftLang

@MainActor struct GallerySourceEditor: View {
    @ObservedObject var session: GalleryDocumentSession
    var component: GalleryComponent? = nil
    @State private var showsComponentUsage = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("OpenUI Lang", systemImage: "curlybraces")
                .font(.headline)
            if let component {
                DisclosureGroup("组件用法", isExpanded: $showsComponentUsage) {
                    Text(component.definition.signature).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Text(component.definition.description).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Text("编辑草稿后点“应用源码”；切换案例或组件库会载入对应原稿。")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $session.draft)
                .font(.system(size: 12, design: .monospaced))
                .autocorrectionDisabled()
                .disabled(session.playback == .streaming || session.playback == .paused)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("应用源码") { session.render() }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.playback == .streaming)
                Button("恢复原稿") { session.restore() }
                Spacer()
                ShareLink(item: session.draft) { Label("导出源码", systemImage: "square.and.arrow.up") }
                    .labelStyle(.iconOnly)
            }
        }
        .padding(16)
        .frame(minWidth: 280, idealWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor struct GalleryPlaybackControls: View {
    @ObservedObject var session: GalleryDocumentSession

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                Text(session.playback.rawValue).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                if session.pendingSuffix != nil {
                    Button("追加流式后缀") { session.appendSuffix() }
                } else if session.playback == .streaming {
                    Button { session.pause() } label: { Label("暂停", systemImage: "pause") }
                } else if session.playback == .paused {
                    Button { session.resume() } label: { Label("继续", systemImage: "play") }
                } else {
                    Button { session.stream() } label: { Label("流式播放", systemImage: "play") }
                }
                Button { session.interrupt() } label: { Label("中断", systemImage: "stop") }
                    .disabled(session.playback != .streaming && session.playback != .paused)
                Button("完整渲染") { session.render() }
                Text("动作仅记录 · 无交易执行").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }
}
