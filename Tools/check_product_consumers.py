#!/usr/bin/env python3
"""Compile public API consumers whose dependency graph contains only one UI product."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CONSUMERS = {
    "OpenSwiftUI": ("OpenIntelligentSwiftUI", "OpenUILibrary.standard()"),
    "OpenIntelligentSwiftUI": ("OpenSwiftUI", "OpenUILibrary.intelligent()"),
}

# Both products compile this exact host. Only their imported UI module and
# makeLibrary() factory differ; all runtime and generation APIs stay identical.
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


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch-root", type=Path, required=True)
    args = parser.parse_args()
    args.scratch_root.mkdir(parents=True, exist_ok=True)
    for product, (peer, factory) in CONSUMERS.items():
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
            (package / "Sources/ConsumerProbe/Consumer.swift").write_text(f'''
import SwiftUI
import OpenUILang
import {product}
#if canImport({peer})
#error("A {product}-only consumer must not build its peer {peer}")
#endif
private func makeLibrary() throws -> OpenUILibrary {{
    try {factory}
}}
''' + HOST_SOURCE)
            subprocess.run(["swift", "build", "--package-path", str(package),
                            "--scratch-path", str(args.scratch_root / product),
                            "--target", "ConsumerProbe"], cwd=ROOT, check=True)
            print(f"{product}: public API consumer compiled without {peer}", flush=True)


if __name__ == "__main__":
    main()
