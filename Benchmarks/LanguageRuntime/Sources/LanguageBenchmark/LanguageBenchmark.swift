import Darwin
import Dispatch
import Foundation
import SwiftLang

private enum BenchmarkError: Error {
    case usage(String)
    case invalidProgram(String)
}

private struct Options {
    var iterations = 500
    var warmup = 10
    var rows = 30
    var output: String?

    init(_ arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let name = arguments[index]
            if name == "--help" {
                print("LanguageBenchmark [--iterations 500] [--warmup 10] [--rows 30] [--output report.json]")
                exit(0)
            }
            guard index + 1 < arguments.count else { throw BenchmarkError.usage("Missing value for " + name) }
            let value = arguments[index + 1]
            switch name {
            case "--output": output = value
            case "--iterations", "--warmup", "--rows":
                guard let number = Int(value), number >= (name == "--warmup" ? 0 : 1) else {
                    throw BenchmarkError.usage("Invalid value for " + name)
                }
                if name == "--iterations" { iterations = number }
                else if name == "--warmup" { warmup = number }
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
    static func main() throws {
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
            ), store: store, schema: schema)
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
        func percentile(_ proportion: Double) -> Double {
            timings[min(timings.count - 1, max(0, Int(ceil(Double(timings.count) * proportion)) - 1))]
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
            "p50Milliseconds": percentile(0.50), "p95Milliseconds": percentile(0.95),
            "maxMilliseconds": timings.last!, "residentSamples": memory,
            "limits": "Language work only: no SwiftUI layout, frame rate or physical-device profile. RSS includes JavaScript VM and allocator retention; growth alone is not evidence of a leak. No internal garbage-collection API is invoked."
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
