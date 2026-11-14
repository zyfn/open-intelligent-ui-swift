# OpenUI native support

This directory owns the general OpenUI native products inside the Swift workspace. It is not another application or a second Intelligent UI implementation.

## Products and ownership

| Product | Location | Responsibility |
| --- | --- | --- |
| `OpenUILang` | `Sources/OpenUILang` + `Sources/COpenUIRegExp` | Shared-core bridge, native values, state/actions, input budgets |
| `OpenUISwiftUI` | `Sources/OpenUISwiftUI` | State facade, renderer/registry, theme/resources and standard 87-component library |
| `SwiftIntelligentUI` | `../Sources/SwiftIntelligentUI` | The existing Intelligent UI component catalog, design system and reader/writer generation contracts |

All products are declared once by the root `Package.swift`. `SwiftIntelligentUI` uses the first two targets directly. An app using only the general library may link only `OpenUISwiftUI`. Do not also resolve `zyfn/openui`: that would introduce a second package defining the same module names. The Gallery Xcode project uses the same root local package, not a private workstation override.

The standard 87-component catalog and Intelligent UI's 60 default / 61 including SearchImage reader catalog remain separate. Select the library matching the stored program and generate the prompt/spec from that library. Moving files does not make these two dialects interchangeable. Intelligent UI's own media, map and text implementations are not silently replaced by the standard library implementations.

## Directory map

```text
OpenUI/
  Sources/          Native products and their bundled resources
  Tests/            Original native regression suites
  Tools/Core/       TypeScript/JavaScriptCore bridge resource builder
  Tools/Presentation/  Catalog, Lucide, rich-text and code resource generators
  Tools/upstream.json  Immutable official-source revisions and patch hash
  Validation/       Node authoring validator (not another parser)
  Fixtures/         Protocol fixture inputs
  Examples/         Standard-library examples and standalone macOS host
  Documentation/    General SDK design, component and protocol references
  IMPORT.json       Source SHA, exact import mapping and runtime-file hashes
  LICENSE           Upstream MIT license; dependency notices stay with resources
```

## Official dependency, without carrying the fork

The language source corresponds to official `@openuidev/lang-core` **1.0.2**, commit `f08a660535e55b5b2a24a0eb68568edaf9e4fe4b`. Maintainer tools fetch that immutable official source, check its tree, and apply the separately hashed positional-signature correction before generation. The adapted tree is pinned to `92152ac52c9d8effdebbe734bedca3c8016b6bac`, the same input used by the imported native release candidate.

This is a **build-time official source dependency**, not a claim that SwiftPM consumes npm packages or that the published npm API exposes every native requirement. The native bridge still needs private source readiness, ordered UTF-16 transport, captured action provenance, safe serialization and bounded-host adapters. These are explicitly documented in `Tools/Core/adaptations.json` and the standalone patch. No parser is reimplemented in Swift, no React UI is shipped, and app launch never fetches JavaScript from a service.

The upstream revision, signature patch, native adapter revision and generated resource hash are independent provenance fields. Changing any of them requires the existing differential/golden tests; never regenerate those fixtures merely to hide a mismatch. Resource generators for the catalog, citations and icons use their own immutable upstream revisions, rather than requiring the deleted monorepo history to exist locally.

Normal consumers need Xcode/SwiftPM and the committed resources only. Node/npm/Git are maintainer tools. The three presentation-tool locks now use public `registry.npmjs.org` URLs with unchanged package integrity digests; internal registry access is not required.

## Verification

Run from the repository root on a Mac with the supported Xcode toolchain:

```sh
python3 Tools/check_openui_integration.py
npm ci --prefix OpenUI/Tools/Core --ignore-scripts
node OpenUI/Tools/Core/build.mjs
node OpenUI/Tools/Core/verify-compatibility.mjs
node --test OpenUI/Validation/validation.test.mjs
# Regeneration must match the committed artifacts for this revision.
git diff --exit-code -- OpenUI/Sources/OpenUILang/Resources
swift test
swift test -c release --filter HostSizingIsolationTests
swift run IntelligentUIGallery --validate-fixtures
python3 Tools/check_lang_compatibility.py
```

`OpenUI/Tools/Core/verify-native.sh` retains general-library golden-contract checks, language ASan and platform compilation using the root package. Historical Intelligent UI contracts still compare against `ed3f6f82abf6f7cc9e307e9bb2eb21073a1f7d79`; source relocation is not an excuse to replace that baseline.

`OPENUI_SNAPSHOT_DIR` enables native visual/measurement exports. A generated PNG, syntax check or successful compile is not an iOS runtime/interaction sign-off. The migration has no automatic release step. The existing public fork release and source integration branch remain intact. This native workspace has its own 0.1.1-rc.21 prerelease; see ../docs/releases/0.1.1-rc.21.md for the dependency repair and validation limits.

## Maintenance rules

1. Keep the runtime neutral: no chat list, payments, navigation database or business vocabulary in these targets.
2. Keep one source owner per native module; do not copy these files into `Sources/SwiftIntelligentUI`.
3. Keep layout measurements free of semantic source submission and business effects.
4. Keep individual subscriptions cancelable even when their underlying resource work is shared.
5. Keep MarkdownUI 2.4.1, Lucide artwork, SF Symbols for internal actions, MapKit, native Canvas charts and existing formula backend for this relocation. Dependency replacement is not bundled into a file move.
6. Prefer improving the source-owned feature over adding a parallel runtime or global cache. Existing tests and component contracts travel with their implementation.
