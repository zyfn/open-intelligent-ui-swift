#!/bin/bash
set -euo pipefail
performance_root="$(cd "$(dirname "$0")/../.." && pwd)"
swift run --configuration release --package-path "$performance_root/Validation/Performance" \
  LanguagePerformanceValidation --output "$performance_root/outputs/verification/performance/language-runtime.json" "$@"
