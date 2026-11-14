import SwiftUI
import OpenUICore
import OpenUILang

@MainActor struct GallerySourceEditor: View {
    @ObservedObject var session: GalleryDocumentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(session.kind.title + " · OpenUI Lang", systemImage: "curlybraces")
                .font(.headline)
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

@MainActor struct GalleryInspector: View {
    @ObservedObject var session: GalleryDocumentSession
    @ObservedObject var state: OpenUIState
    @State private var snapshot = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("诊断与动作").font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.isInterrupted ? "文档已中断" : state.isComplete ? "文档已完成" : "文档生成中")
                        .font(.subheadline.weight(.medium))
                    Text("source revision \(state.sourceRevision) · presentation \(state.presentationRevision)")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                    if state.errors.isEmpty { Label("当前无解析/运行时错误", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                    else {
                        Text(state.errors.map(\.message).joined(separator: "\n\n"))
                            .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    }
                }
                Divider()
                HStack {
                    Text("状态快照").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("刷新快照") { snapshot = session.currentStateJSON }
                }
                Text(snapshot).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                Divider()
                Text("最近动作 · 最多 30 条").font(.subheadline.weight(.semibold))
                if session.actions.isEmpty {
                    Text("点击案例中的按钮、提交表单或链接后，在此检查 action 参数与提交时的 formState。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(session.actions) { record in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.type).font(.subheadline.weight(.medium))
                        if !record.message.isEmpty { Text(record.message).font(.caption) }
                        Text("params: " + record.parameters).font(.system(size: 11, design: .monospaced))
                        Text("formState: " + record.formState).font(.system(size: 11, design: .monospaced))
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(16)
        }
        .frame(minWidth: 280, idealWidth: 360, maxWidth: .infinity)
        .onAppear { snapshot = session.currentStateJSON }
    }
}
