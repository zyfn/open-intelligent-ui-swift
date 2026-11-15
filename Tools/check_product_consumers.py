#!/usr/bin/env python3
"""Build and run one isolated consumer per public product, rejecting higher/peer modules."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN_MODULES = {
    "OpenUILang": ("OpenUICore", "OpenSwiftUI", "OpenIntelligentSwiftUI"),
    "OpenUICore": ("OpenSwiftUI", "OpenIntelligentSwiftUI"),
    "OpenSwiftUI": ("OpenIntelligentSwiftUI",),
    "OpenIntelligentSwiftUI": ("OpenSwiftUI",),
}
UI_FACTORIES = {
    "OpenSwiftUI": "OpenUILibrary.standard()",
    "OpenIntelligentSwiftUI": "OpenUILibrary.intelligent()",
}
HOST_PROGRAMS = {
    "OpenUICore": ('$probe = "ready"\nroot = Notice($probe)', "Notice"),
    "OpenSwiftUI": ('$probe = "ready"\nroot = Stack([TextContent($probe)])', "Stack"),
    "OpenIntelligentSwiftUI": ('$probe = "ready"\nroot = Col([Text($probe)])', "Col"),
}

# Core and both UI products execute this exact host. Only the imported module,
# makeLibrary() factory and sample contract differ; their public APIs stay identical.
HOST_SOURCE = """
@MainActor public func makeConsumer(
    source: String,
    toolProvider: ToolProvider? = nil,
    persistedState: [String: Value] = [:],
    onAction: @escaping (ActionEvent) -> Void
) throws -> (view: OpenUIView, state: OpenUIState, prompt: String, writer: LibrarySpec,
             writerJSON: String, reader: LibrarySpec) {
    let library = try makeLibrary()
    let state = library.makeState(toolProvider: toolProvider, persistedState: persistedState)
    state.onAction = onAction
    state.push(source)
    state.complete()
    return (OpenUIView(state: state, library: library), state, library.systemPrompt,
            library.specification, library.specificationJSON, library.readerSpecification)
}

@MainActor private func runConsumer(source: String, expectedRoot: String) throws {
    let consumer = try makeConsumer(source: source, onAction: { _ in })
    defer { consumer.state.reset() }
    precondition(consumer.state.root?.typeName == expectedRoot, "Missing consumer root")
    precondition(consumer.state.isComplete, "Consumer stream did not complete")
    precondition(consumer.state.errors.isEmpty, "Consumer program failed to parse or evaluate")
    precondition(!consumer.prompt.isEmpty, "Missing generation prompt")
    precondition(!consumer.writer.components.isEmpty, "Missing writer specification")
    precondition(!consumer.writerJSON.isEmpty, "Missing writer JSON")
    precondition(!consumer.reader.components.isEmpty, "Missing reader specification")
    precondition(consumer.state.stateValue("$probe") == .string("ready"), "Missing initial state")
    consumer.state.setState("$probe", value: .string("updated"))
    precondition(consumer.state.stateValue("$probe") == .string("updated"), "State update failed")
    precondition(consumer.state.root?.typeName == expectedRoot, "State update lost the root")
    precondition(consumer.state.errors.isEmpty, "State update failed to evaluate")
}
"""

LANG_SOURCE = r"""
import OpenUILang

public func parseConsumer(source: String) throws -> (
    parsed: ParseResult, streamed: ParseResult, specification: LibrarySpec
) {
    let library = try createLibrary(
        components: [
            defineComponent(
                name: "Notice",
                description: "Consumer-owned text contract",
                params: [ParamDef(
                    name: "text", required: true,
                    schema: .object([("type", .string("string"))])
                )]
            )
        ],
        root: "Notice"
    )
    let schema = library.toSchema()
    let parsed = createParser(schema: schema).parse(source)
    let stream = createStreamingParser(schema: schema)
    let streamed = stream.push(source, complete: true)
    return (parsed, streamed, library.toSpec())
}

@main struct ConsumerProbe {
    static func main() throws {
        let consumer = try parseConsumer(source: #"root = Notice("ready")"#)
        for result in [consumer.parsed, consumer.streamed] {
            precondition(result.root?.typeName == "Notice", "Missing parsed root")
            precondition(!result.meta.incomplete, "Consumer parse did not complete")
            precondition(result.meta.errors.isEmpty, "Consumer program failed to parse")
        }
        precondition(!consumer.specification.components.isEmpty, "Missing language specification")
        let store = createStore()
        defer { store.dispose() }
        store.initialize(defaults: [], persisted: [:])
        store.set("$probe", value: .string("updated"), pristine: false)
        precondition(store.get("$probe") == .string("updated"), "Language store update failed")
    }
}
"""

CORE_FACTORY = """
private func makeLibrary() throws -> OpenUILibrary {
    let components = try OpenUIComponentLibrary(
        components: [
            OpenUIComponent(
                name: "Notice",
                description: "Consumer-owned native text",
                params: [OpenUIParameter.string("text")]
            ) { context in
                Text(context.string("text") ?? "")
            }
        ],
        root: "Notice"
    )
    return OpenUILibrary(components: components)
}
"""


def consumer_source(product: str) -> str:
    guards = "\n".join(
        f'#if canImport({forbidden})\n'
        f'#error("A {product}-only consumer must not build {forbidden}")\n'
        '#endif'
        for forbidden in FORBIDDEN_MODULES[product]
    )
    if product == "OpenUILang":
        # SwiftUI is a platform module on macOS, so canImport(SwiftUI) cannot
        # prove a package dependency. check_module_boundaries.py rejects its
        # import in Lang sources; this consumer imports only OpenUILang.
        return guards + LANG_SOURCE
    factory = CORE_FACTORY if product == "OpenUICore" else f'''
private func makeLibrary() throws -> OpenUILibrary {{
    try {UI_FACTORIES[product]}
}}
'''
    source, expected_root = HOST_PROGRAMS[product]
    return f'''import SwiftUI
import OpenUILang
import {product}
{guards}
''' + factory + HOST_SOURCE + f'''
@main struct ConsumerProbe {{
    @MainActor static func main() throws {{
        try runConsumer(source: {json.dumps(source, ensure_ascii=False)}, expectedRoot: {json.dumps(expected_root, ensure_ascii=False)})
    }}
}}
'''


def consumer_package(product: str) -> str:
    return f'''// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "{product}Consumer",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ConsumerProbe", targets: ["ConsumerProbe"])],
    dependencies: [.package(name: "OpenUISwiftSDK", path: {json.dumps(str(ROOT), ensure_ascii=False)})],
    targets: [.executableTarget(name: "ConsumerProbe", dependencies: [
        .product(name: "{product}", package: "OpenUISwiftSDK")
    ], swiftSettings: [.swiftLanguageMode(.v5)])]
)
'''


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch-root", type=Path, required=True)
    args = parser.parse_args()
    if shutil.which("swift") is None:
        parser.error("Swift toolchain not found; run this check on macOS with Swift 6 / Xcode installed")
    args.scratch_root.mkdir(parents=True, exist_ok=True)
    for product, forbidden in FORBIDDEN_MODULES.items():
        with tempfile.TemporaryDirectory(prefix=product + "-consumer-") as directory:
            package = Path(directory)
            (package / "Sources/ConsumerProbe").mkdir(parents=True)
            (package / "Package.swift").write_text(consumer_package(product))
            (package / "Sources/ConsumerProbe/Consumer.swift").write_text(consumer_source(product))
            subprocess.run(["swift", "run", "--package-path", str(package),
                            "--scratch-path", str(args.scratch_root / product),
                            "ConsumerProbe"], cwd=ROOT, check=True)
            print(f"{product}: public API consumer built and ran without {', '.join(forbidden)}", flush=True)


if __name__ == "__main__":
    main()
