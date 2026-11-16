import os

/// Instruments intervals only; no source, tool arguments, or user values are
/// logged. Disabled tracing does not allocate interval state or change work.
enum NativeRuntimeTrace {
    private static let signposter = OSSignposter(subsystem: "org.openui.swiftlang", category: "Runtime")

    static func measure<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        guard signposter.isEnabled else { return try body() }
        let interval = signposter.beginInterval(name, id: signposter.makeSignpostID())
        defer { signposter.endInterval(name, interval) }
        return try body()
    }
}
