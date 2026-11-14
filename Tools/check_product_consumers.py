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
    "OpenSwiftUI": ("OpenIntelligentSwiftUI", """
        let library = try OpenUIStandardComponents.library()
        let state = OpenUIState(schema: library.library.toSchema())
        return OpenUIRenderer(state: state, registry: library.registry)
    """),
    "OpenIntelligentSwiftUI": ("OpenSwiftUI", """
        let library = try IntelligentUILibrary()
        let state = library.makeState()
        return IntelligentUIView(state: state, library: library)
    """),
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch-root", type=Path, required=True)
    args = parser.parse_args()
    args.scratch_root.mkdir(parents=True, exist_ok=True)
    for product, (peer, body) in CONSUMERS.items():
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
import {product}
#if canImport({peer})
#error("A {product}-only consumer must not build its peer {peer}")
#endif
@MainActor public func makeConsumer() throws -> some View {{
{body}
}}
''')
            subprocess.run(["swift", "build", "--package-path", str(package),
                            "--scratch-path", str(args.scratch_root / product),
                            "--target", "ConsumerProbe"], cwd=ROOT, check=True)
            print(f"{product}: public API consumer compiled without {peer}", flush=True)


if __name__ == "__main__":
    main()
