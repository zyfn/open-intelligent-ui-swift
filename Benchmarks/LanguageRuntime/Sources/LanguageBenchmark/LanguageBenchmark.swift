import Darwin
import Dispatch
import Foundation
import Combine
import SwiftLang
import os

private enum BenchmarkError: Error {
    case usage(String)
    case invalidProgram(String)
}

private struct Options {
    var iterations = 500
    var warmup = 10
    var rows = 30
    var streamIterations = 20
    var chunkUnits = 128
    var output: String?

    init(_ arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let name = arguments[index]
            if name == "--help" {
                print("LanguageBenchmark [--iterations 500] [--warmup 10] [--rows 30] [--stream-iterations 20] [--chunk-units 128] [--output report.json]")
                exit(0)
            }
            guard index + 1 < arguments.count else { throw BenchmarkError.usage("Missing value for " + name) }
            let value = arguments[index + 1]
            switch name {
            case "--output": output = value
            case "--iterations", "--warmup", "--rows", "--stream-iterations", "--chunk-units":
                guard let number = Int(value), number >= (name == "--warmup" ? 0 : 1) else {
                    throw BenchmarkError.usage("Invalid value for " + name)
                }
                if name == "--iterations" { iterations = number }
                else if name == "--warmup" { warmup = number }
                else if name == "--stream-iterations" { streamIterations = number }
                else if name == "--chunk-units" { chunkUnits = number }
                else { rows = number }
            default: throw BenchmarkError.usage("Unknown option: " + name)
            }
            index += 2
        }
    }
}

private func residentBytes() -> UInt64? {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return status == KERN_SUCCESS ? UInt64(info.resident_size) : nil
}

@main private enum LanguageBenchmark {
    @MainActor static func main() throws {
        let options = try Options(Array(CommandLine.arguments.dropFirst()))
        // These contracts describe a language workload, not rendered UI views.
        let schema = LibrarySchema(components: [
            "BenchmarkColumn": [ParamDef(name: "children", required: true)],
            "BenchmarkText": [ParamDef(name: "value", required: true)]
        ], callDefs: builtinCallDefs, rootComponent: "BenchmarkColumn")
        let rows = (0..<options.rows).map { "BenchmarkText(\"row \($0) \" + $n)" }.joined(separator: ",")
        let source = "$n = 1\nroot = BenchmarkColumn([" + rows + "])"

        func iteration() throws {
            let result = createParser(schema: schema).parse(source)
            let store = createStore()
            store.initialize(defaults: result.stateDeclarations, persisted: [:])
            let evaluator = Evaluator(context: EvaluationContext(
                getState: { store.get($0) ?? .null }, resolveRef: { _ in .null }
            ), schema: schema)
            guard result.meta.errors.isEmpty, evaluator.evaluateRoot(result)?.typeName == "BenchmarkColumn" else {
                throw BenchmarkError.invalidProgram(String(describing: result.meta.errors))
            }
            for value in 2...4 {
                store.set("$n", value: .number(Double(value)), pristine: false)
                guard evaluator.evaluateRoot(result)?.typeName == "BenchmarkColumn" else {
                    throw BenchmarkError.invalidProgram("State update did not evaluate the workload root")
                }
            }
        }

        for _ in 0..<options.warmup { try autoreleasepool { try iteration() } }
        var timings: [Double] = []
        var memory: [[String: Any]] = []
        func sampleMemory(after count: Int) {
            if let bytes = residentBytes() { memory.append(["iteration": count, "residentBytes": bytes]) }
        }
        sampleMemory(after: 0)
        for index in 0..<options.iterations {
            try autoreleasepool {
                let start = DispatchTime.now().uptimeNanoseconds
                try iteration()
                let elapsed = DispatchTime.now().uptimeNanoseconds - start
                timings.append(Double(elapsed) / 1_000_000)
            }
            if (index + 1) % 100 == 0 || index + 1 == options.iterations {
                sampleMemory(after: index + 1)
            }
        }
        timings.sort()
        func statistics(_ samples: [Double]) -> [String: Double] {
            let sorted = samples.sorted()
            func percentile(_ proportion: Double) -> Double {
                sorted[min(sorted.count - 1, max(0, Int(ceil(Double(sorted.count) * proportion)) - 1))]
            }
            return ["p50Milliseconds": percentile(0.50), "p95Milliseconds": percentile(0.95),
                    "maxMilliseconds": sorted.last ?? 0]
        }
        // Exercise the public MainActor adapter as well as the parser-only
        // workload above. A changing tail is distinct from repeatedly setting
        // an unchanged buffer. The generated workload is ASCII, so slicing at
        // these byte boundaries also gives exact UTF-16 chunk sizes.
        let names = (0..<options.rows).map { "row\($0)" }
        let declarations = names.enumerated().map {
            "\($0.element)=BenchmarkText(\"stable row \($0.offset)\")"
        }
        let streamingSource = (["root=BenchmarkColumn([" + (names + ["tail"]).joined(separator: ",") + "])"]
            + declarations + ["tail=BenchmarkText(\"" + String(repeating: "streaming text ", count: 128) + "\")"])
            .joined(separator: "\n")
        let wire = Array(streamingSource.utf8)
        let chunks = stride(from: 0, to: wire.count, by: options.chunkUnits).map {
            String(decoding: wire[$0..<min(wire.count, $0 + options.chunkUnits)], as: UTF8.self)
        }
        var pushSamples: [Double] = [], completionSamples: [Double] = [], streamSamples: [Double] = []
        var parseCallbacks = 0, publications = 0, streamingComponents = 0
        let signposter = OSSignposter(subsystem: "org.openui.benchmarks", category: "LanguageRuntime")
        let pushSignpostsEnabled = signposter.isEnabled
        @MainActor func streamIteration(record: Bool, iteration: Int) throws {
            let state = OpenUIState(schema: schema)
            state.onParseResult = { _ in if record { parseCallbacks += 1 } }
            let subscription = state.objectWillChange.sink { if record { publications += 1 } }
            defer { subscription.cancel() }
            let started = DispatchTime.now().uptimeNanoseconds
            for (chunkIndex, chunk) in chunks.enumerated() {
                let interval = pushSignpostsEnabled ? signposter.beginInterval("Public push",
                    id: signposter.makeSignpostID(), "iteration=\(iteration) chunk=\(chunkIndex)") : nil
                let start = DispatchTime.now().uptimeNanoseconds
                state.push(chunk)
                let elapsed = DispatchTime.now().uptimeNanoseconds - start
                if let interval { signposter.endInterval("Public push", interval) }
                if record { pushSamples.append(Double(elapsed) / 1_000_000) }
            }
            let completionStart = DispatchTime.now().uptimeNanoseconds
            state.complete()
            let completed = DispatchTime.now().uptimeNanoseconds
            guard state.errors.isEmpty, state.root?.typeName == "BenchmarkColumn", !state.isInterrupted else {
                throw BenchmarkError.invalidProgram("Streaming adapter: " + String(describing: state.errors))
            }
            guard let root = state.root,
                  PropValue.children(root).count == options.rows + 1,
                  PropValue.string(PropValue.children(root).last!, "value") == String(repeating: "streaming text ", count: 128) else {
                throw BenchmarkError.invalidProgram("Streaming lost a completed sibling or its final tail")
            }
            streamingComponents = PropValue.children(root).count + 1
            if record {
                completionSamples.append(Double(completed - completionStart) / 1_000_000)
                streamSamples.append(Double(completed - started) / 1_000_000)
            }
        }
        for index in 0..<min(options.warmup, 3) { try autoreleasepool { try streamIteration(record: false, iteration: -index - 1) } }
        for index in 0..<options.streamIterations { try autoreleasepool { try streamIteration(record: true, iteration: index) } }
        // Tool responses can be wide without being deeply nested. Measure the
        // native ordered-object construction that happens outside the JS work
        // counter; a small final UI must not conceal quadratic input work.
        let fieldCount = 10_000
        var fields = (0..<fieldCount).map { ObjectField(key: "field\($0)", value: .number(Double($0))) }
        fields.append(ObjectField(key: "field0", value: .number(-1)))
        var objectSamples: [Double] = []
        for _ in 0..<options.streamIterations {
            try autoreleasepool {
                let start = DispatchTime.now().uptimeNanoseconds
                let object = OpenUIObject(fields)
                objectSamples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                guard object.count == fieldCount, object.first?.value == .number(-1),
                      object.last?.key == OpenUIString("field\(fieldCount - 1)") else {
                    throw BenchmarkError.invalidProgram("Wide-object ordering or last-write semantics changed")
                }
            }
        }
        let languageStatistics = statistics(timings)
        // Derive positions after measurement, without extra allocations or
        // instrumentation inside the timed push. A maximum without its input
        // position cannot distinguish late tree growth from a periodic spike.
        let slowestPushes: [[String: Any]] = pushSamples.enumerated()
            .sorted { $0.element > $1.element }.prefix(10).map { sample in
                let chunk = sample.offset % chunks.count
                return ["iteration": sample.offset / chunks.count,
                        "chunk": chunk,
                        "sourceUTF16Units": min(wire.count, (chunk + 1) * options.chunkUnits),
                        "milliseconds": sample.element]
            }
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let report: [String: Any] = [
            "benchmark": "language-runtime", "configuration": configuration,
            "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
            "processorCount": ProcessInfo.processInfo.processorCount,
            "programBytes": source.utf8.count, "components": options.rows + 1,
            "iterations": options.iterations, "warmupIterations": options.warmup,
            "perIteration": "parse + initial render-tree evaluation + 3 state writes and reevaluations",
            "p50Milliseconds": languageStatistics["p50Milliseconds"]!, "p95Milliseconds": languageStatistics["p95Milliseconds"]!,
            "maxMilliseconds": timings.last!, "residentSamples": memory,
            "streaming": [
                "workload": "public OpenUIState.push with stable siblings and a changing text tail, then complete",
                "components": streamingComponents, "stableTextComponents": options.rows,
                "pushSignpostsEnabled": pushSignpostsEnabled,
                "iterations": options.streamIterations, "chunkUTF16Units": options.chunkUnits,
                "chunksPerIteration": chunks.count, "sourceUTF16Units": streamingSource.utf16.count,
                "push": statistics(pushSamples), "complete": statistics(completionSamples),
                "slowestPushes": slowestPushes,
                "wholeStream": statistics(streamSamples), "parseCallbacks": parseCallbacks,
                "objectWillChangePublications": publications,
                "instrumentation": "Callbacks count synchronous publications; they do not count SwiftUI body evaluations or frames."
            ] as [String: Any],
            "orderedFieldConstruction": ["fields": fieldCount, "iterations": options.streamIterations,
                                           "timing": statistics(objectSamples)] as [String: Any],
            "limits": "Language and public MainActor adapter work only: no SwiftUI layout, frame rate or physical-device profile. RSS samples cover the parser workload and include JavaScript VM and allocator retention; growth alone is not evidence of a leak. No internal garbage-collection API is invoked."
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        if let path = options.output {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        print(String(decoding: data, as: UTF8.self))
    }
}
