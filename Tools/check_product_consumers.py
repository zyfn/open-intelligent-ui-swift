#!/usr/bin/env python3
"""Compile one isolated consumer per public product and reject higher/peer modules."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
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

# Core and both UI products compile this exact host. Only the imported module
# and makeLibrary() factory differ; runtime and generation APIs stay identical.
HOST_SOURCE = """
@MainActor public func makeConsumer(
    source: String,
    toolProvider: ToolProvider? = nil,
    persistedState: [String: Value] = [:],
    onAction: @escaping (ActionEvent) -> Void
) throws -> (view: OpenUIView, prompt: String, writer: LibrarySpec,
             writerJSON: String, reader: LibrarySpec) {
    let library = try makeLibrary()
    let state = library.makeState(toolProvider: toolProvider, persistedState: persistedState)
    state.onAction = onAction
    state.push(source)
    state.complete()
    return (OpenUIView(state: state, library: library), library.systemPrompt,
            library.specification, library.specificationJSON, library.readerSpecification)
}
"""

LANG_SOURCE = """
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
    return f'''import SwiftUI
import OpenUILang
import {product}
{guards}
''' + factory + HOST_SOURCE


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch-root", type=Path, required=True)
    args = parser.parse_args()
    args.scratch_root.mkdir(parents=True, exist_ok=True)
    for product, forbidden in FORBIDDEN_MODULES.items():
        with tempfile.TemporaryDirectory(prefix=product + "-consumer-") as directory:
            package = Path(directory)
            (package / "Sources/ConsumerProbe").mkdir(parents=True)
            (package / "Package.swift").write_text(f'''// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "{product}Consumer",
    platforms: [.macOS(.v13)],
    products: [.library(name: "ConsumerProbe", targets: ["ConsumerProbe"])],
    dependencies: [.package(name: "OpenUISwiftSDK", path: {json.dumps(str(ROOT))})],
    targets: [.target(name: "ConsumerProbe", dependencies: [
        .product(name: "{product}", package: "OpenUISwiftSDK")
    ], swiftSettings: [.swiftLanguageMode(.v5)])]
)
''')
            (package / "Sources/ConsumerProbe/Consumer.swift").write_text(consumer_source(product))
            subprocess.run(["swift", "build", "--package-path", str(package),
                            "--scratch-path", str(args.scratch_root / product),
                            "--target", "ConsumerProbe"], cwd=ROOT, check=True)
            print(f"{product}: public API consumer compiled without {', '.join(forbidden)}", flush=True)


if __name__ == "__main__":
    main()
