#!/bin/bash
set -euo pipefail
benchmark_root="$(cd "$(dirname "$0")/../.." && pwd)"
swift run --configuration release --package-path "$benchmark_root/Benchmarks/LanguageRuntime" \
  LanguageBenchmark --output "$benchmark_root/outputs/benchmarks/language-runtime.json" "$@"
