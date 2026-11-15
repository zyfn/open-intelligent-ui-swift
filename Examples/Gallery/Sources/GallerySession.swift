import Foundation
import Combine
import SwiftLang

struct GalleryActionRecord: Identifiable {
    let id = UUID()
    let type: String
    let message: String
    let parameters: String
    let formState: String
}

enum GalleryPlayback: String {
    case ready = "就绪", streaming = "流式播放中", paused = "已暂停"
    case complete = "已完成", interrupted = "已中断"
}

/// Owns exactly one library/document pairing. Preview geometry is deliberately
/// absent: resizing/zooming cannot reset the program or its edited form state.
@MainActor final class GalleryDocumentSession: ObservableObject, Identifiable {
    let id = UUID()
    let kind: GalleryLibrary
    let library: OpenUILibrary
    let state: OpenUIState
    let originalSource: String
    let title: String
    @Published var draft: String
    @Published private(set) var playback: GalleryPlayback = .ready
    @Published private(set) var actions: [GalleryActionRecord] = []
    @Published private(set) var pendingSuffix: String?
    private var streamTask: Task<Void, Never>?
    private var streamCharacters: [Character] = []
    private var streamPosition = 0
    private var streamEpoch = UUID()

    init(kind: GalleryLibrary, source: String, title: String, suffix: String? = nil) throws {
        self.kind = kind
        let library = try kind.makeLibrary()
        self.library = library
        self.state = library.makeState(toolProvider: GalleryToolProvider())
        self.originalSource = source + (suffix ?? "")
        self.draft = source + (suffix ?? "")
        self.title = title
        self.pendingSuffix = suffix
        state.onAction = { [weak self] event in self?.record(event) }
        state.setSource(source, streaming: suffix != nil)
        playback = suffix == nil ? .complete : .paused
    }

    deinit { streamTask?.cancel() }

    func render() {
        cancelTask()
        pendingSuffix = nil
        state.reset()
        state.setSource(draft)
        playback = .complete
    }

    func restore() { pendingSuffix = nil; draft = originalSource; render() }

    func stream(chunkSize: Int = 48, intervalNanoseconds: UInt64 = 60_000_000) {
        cancelTask()
        pendingSuffix = nil
        state.reset()
        streamCharacters = Array(draft)
        streamPosition = 0
        resume(chunkSize: chunkSize, intervalNanoseconds: intervalNanoseconds)
    }

    func resume(chunkSize: Int = 48, intervalNanoseconds: UInt64 = 60_000_000) {
        guard pendingSuffix == nil else { return }
        cancelTask()
        let epoch = streamEpoch
        playback = .streaming
        let chunkSize = max(1, chunkSize)
        streamTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.streamEpoch == epoch else { return }
                guard self.streamPosition < self.streamCharacters.count else {
                    self.state.complete()
                    self.playback = .complete
                    self.streamTask = nil
                    return
                }
                let end = min(self.streamPosition + chunkSize, self.streamCharacters.count)
                self.state.push(String(self.streamCharacters[self.streamPosition..<end]))
                self.streamPosition = end
                do { try await Task.sleep(nanoseconds: intervalNanoseconds) }
                catch { return }
            }
        }
    }

    func pause() {
        guard playback == .streaming else { return }
        cancelTask()
        playback = .paused
    }

    func interrupt() {
        cancelTask()
        pendingSuffix = nil
        if !state.isComplete { state.interrupt() }
        if playback == .streaming || playback == .paused { playback = .interrupted }
    }

    func appendSuffix() {
        guard let suffix = pendingSuffix, !state.isComplete else { return }
        cancelTask()
        state.push(suffix)
        state.complete()
        pendingSuffix = nil
        playback = .complete
    }

    func retire() {
        cancelTask()
        state.onAction = nil
        state.reset()
    }

    private func cancelTask() {
        streamEpoch = UUID()
        streamTask?.cancel()
        streamTask = nil
    }

    func recordLink(_ url: URL) {
        append(.init(type: "OpenURL", message: "Gallery 仅记录链接，不执行跳转",
                     parameters: url.absoluteString, formState: currentStateJSON))
    }

    private func record(_ event: ActionEvent) {
        append(.init(type: event.type.displayString, message: event.humanFriendlyMessage.displayString,
                     parameters: Self.json(event.params), formState: Self.json(event.formState ?? [])))
    }

    private func append(_ record: GalleryActionRecord) {
        actions.insert(record, at: 0)
        if actions.count > 30 { actions.removeLast(actions.count - 30) }
    }

    var currentStateJSON: String {
        Self.json(state.snapshotState().sorted { $0.key.displayString < $1.key.displayString }.map { ($0.key, $0.value) })
    }

    private static func json(_ values: [(OpenUIString, Value)]) -> String {
        let fields = values.map { ObjectField(key: $0.0, value: $0.1) }
        return (try? Value.object(fields).jsonString()) ?? "无法序列化当前值"
    }
}

@MainActor final class GalleryModel: ObservableObject {
    @Published private(set) var entries: [GalleryEntry] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var selectedLibrary: GalleryLibrary
    @Published private(set) var components: [GalleryComponent] = []
    @Published private(set) var session: GalleryDocumentSession?
    @Published private(set) var failure: String?
    let resources: OpenUIResourceContext?
    private let resourceRoot: URL?
    private var selections: [GalleryLibrary: String] = [:]
    var selectedEntry: GalleryEntry? { entries.first { $0.id == selectedID } }
    var selectedComponent: GalleryComponent? { components.first { $0.id == selectedID } }

    init(options: GalleryOptions = GalleryOptions(), catalog: GalleryCatalog? = nil, resourceRoot: URL? = nil) {
        selectedLibrary = options.library
        do {
            let root = try resourceRoot ?? GalleryResources.root()
            let loader = try GalleryImageLoader(resourceRoot: root)
            let loaded = try catalog?.entries ?? GalleryCatalog(resourceRoot: root).entries
            let componentItems = try GalleryComponent.load(options.library, resourceRoot: root)
            resources = OpenUIResourceContext(loader: loader)
            self.resourceRoot = root
            entries = loaded
            components = componentItems
        } catch {
            resources = nil
            self.resourceRoot = nil
            failure = error.localizedDescription
            return
        }
        if let program = options.program {
            do {
                let source = try GalleryImportedProgram.read(url: URL(fileURLWithPath: program), library: selectedLibrary)
                let suffix = try options.streamSuffix.map {
                    try GalleryImportedProgram.readRaw(url: URL(fileURLWithPath: $0))
                }
                session = try GalleryDocumentSession(kind: selectedLibrary, source: source,
                                                      title: URL(fileURLWithPath: program).lastPathComponent, suffix: suffix)
            } catch { failure = error.localizedDescription }
        } else if let id = options.caseID {
            if let entry = entries.first(where: { $0.item.id == id || $0.id == id }) { select(entry.id) }
            else if components.contains(where: { $0.id == id }) { select(id) }
            else { failure = "找不到案例：\(id)" }
        } else if let first = entries.first(where: { $0.supports(selectedLibrary) }) { select(first.id) }
    }

    func select(_ id: String) {
        let entry = entries.first { $0.id == id && $0.supports(selectedLibrary) }
        let component = components.first { $0.id == id }
        guard entry != nil || component != nil else { return }
        if id == selectedID, session?.kind == selectedLibrary { return }
        session?.retire(); session = nil
        selectedID = id
        selections[selectedLibrary] = id
        do {
            let source = try component?.source ?? entry!.source(for: selectedLibrary)
            session = try GalleryDocumentSession(kind: selectedLibrary, source: source,
                                                 title: component?.name ?? entry!.item.title)
            failure = nil
        } catch { failure = error.localizedDescription }
    }

    func selectLibrary(_ library: GalleryLibrary) {
        guard selectedLibrary != library else { return }
        let previousID = selectedID
        if let id = selectedID { selections[selectedLibrary] = id }
        session?.retire(); session = nil
        selectedID = nil
        selectedLibrary = library
        do {
            guard let root = resourceRoot else { return }
            components = try GalleryComponent.load(library, resourceRoot: root)
            let matchingScene = entries.first { $0.id == previousID && $0.section == .cases && $0.supports(library) }?.id
            let id = selections[library] ?? matchingScene ?? entries.first { $0.section == .cases && $0.supports(library) }?.id
            if let id { select(id) }
        } catch {
            components = []
            failure = error.localizedDescription
        }
    }

    func importProgram(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let source = try GalleryImportedProgram.read(url: url, library: selectedLibrary)
            let next = try GalleryDocumentSession(kind: selectedLibrary, source: source, title: url.lastPathComponent)
            session?.retire()
            selectedID = nil
            session = next
            failure = nil
        } catch { failure = error.localizedDescription }
    }

    func report(_ error: Error) { failure = error.localizedDescription }
}
