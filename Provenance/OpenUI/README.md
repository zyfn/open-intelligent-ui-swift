# OpenUI source provenance

[IMPORT.json](IMPORT.json) records the initial source import from
`zyfn/openui@f3dfa1d0b479c131b6d4268e81961186f22ff09c`, tree
`3e2704beeb571bb99f7de41abe4484340a3ce03d`. Its recorded paths and hashes describe
that import and remain byte-preserved. [LICENSE](LICENSE) preserves the imported
license bytes. Later reviewed changes are recorded in this repository's Git
history; the import record is not a current-file checksum manifest.

The SDK now has one root package. Active sources and tests live in `Sources/`
and `Tests/`; generator tools, conformance data, examples and documentation live
in the corresponding root directories. The old paths inside `IMPORT.json` are
historical evidence, not current package entry points.

## Current reproducible inputs

- [Tools/upstream.json](../../Tools/upstream.json) pins the official upstream
  build inputs, the original and adapted language trees, and the source patch.
- [Core adaptations](../../Tools/Core/adaptations.json) records the platform,
  compatibility and bounded-execution changes embedded by the build.
- [Core resource manifest](../../Sources/OpenUILang/Resources/core-manifest.json)
  records the actual bundle, dependency-lock and adapter hashes.
- [RC21 source repair manifest](../../Validation/source-rc21/manifest.json) and
  its [exact patch](../../Validation/source-rc21/source-rc21-fixes.patch) describe
  a separately verified repair candidate on the frozen imported source. The
  candidate is explicitly patched; it is not represented as untouched upstream.

Run `python3 Tools/check_openui_integration.py` from the repository root to check
the current integration. The source repair tool validates the frozen base,
allowed file set, before/after hashes and complete candidate tree. See
[validation and dependency provenance](../../docs/validation-and-security.md)
for the gate and evidence boundaries.
