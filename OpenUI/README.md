# OpenUI import provenance and maintainer tools

This directory retains the imported native SDK's provenance, build tools, fixtures, validators, examples and historical documentation. Current Swift source and tests live in the repository-root `Sources/` and `Tests/` directories. See the [current architecture](../docs/architecture.md) and [SDK quick start](../README.md) for product selection and integration.

## Products and ownership

| Product | Location | Responsibility |
| --- | --- | --- |
| `OpenUILang` | `../Sources/OpenUILang` + `../Sources/COpenUIRegExp` | Language bridge, values, Store, action/query semantics and input budgets |
| `OpenUICore` | `../Sources/OpenUICore` | Shared native state, context/host, registration, rendering identity, bindings and resource infrastructure |
| `OpenSwiftUI` | `../Sources/OpenSwiftUI` | Standard component catalog, theme, layout, controls and media presentation |
| `OpenIntelligentSwiftUI` | `../Sources/OpenIntelligentSwiftUI` | Intelligent UI component catalog, design system and reader/writer generation contracts |

All products are declared once by the root [Package.swift](../Package.swift). The two UI libraries depend on `OpenUICore` and `OpenUILang`, and neither depends on the other UI library. An app can link only `OpenSwiftUI`, only `OpenIntelligentSwiftUI`, or use `OpenUICore` to register its own components. Both UI libraries expose the same Core-owned `OpenUIState`; each still requires its own matching schema and registry. Do not also resolve `zyfn/openui`: that would introduce a second package defining the same module names. The Gallery Xcode project uses the same root local package.

The standard 87-component catalog and Intelligent UI's 60 default / 61 including SearchImage reader catalog remain separate. Select the library matching the stored program and generate the prompt/spec from that library. Moving files does not make these two dialects interchangeable. Intelligent UI's own media, map and text implementations are not silently replaced by the standard library implementations.

## Directory map

Repository-root `Sources/` and `Tests/` are the only current native source and test owners. The former `OpenUI/Sources` and `OpenUI/Tests` compatibility symlinks have been removed. This retained directory contains:

```text
OpenUI/
  Tools/Core/       TypeScript/JavaScriptCore bridge resource builder
  Tools/Presentation/  Catalog, Lucide, rich-text and code resource generators
  Tools/upstream.json  Immutable official-source revisions and patch hash
  Validation/       Node authoring validator (not another parser)
  Fixtures/         Protocol fixture inputs
  Examples/         Standard-library examples and standalone macOS host
  Documentation/    Imported design, component and protocol references
  IMPORT.json       Source SHA, exact import mapping and runtime-file hashes
  LICENSE           Upstream MIT license; dependency notices stay with resources
```

`IMPORT.json` preserves the original import mapping and hashes as evidence; its historical paths are not the current package layout. Current module names, source locations and host ownership are documented in [docs/architecture.md](../docs/architecture.md). Older names such as `OpenUISwiftUI` and `SwiftIntelligentUI` may still appear in historical records.

## Official dependency, without carrying the fork

The language source corresponds to official `@openuidev/lang-core` **1.0.2**, commit `f08a660535e55b5b2a24a0eb68568edaf9e4fe4b`. Maintainer tools fetch that immutable official source, check its tree, and apply the separately hashed positional-signature correction before generation. The adapted tree is pinned to `92152ac52c9d8effdebbe734bedca3c8016b6bac`, the same input used by the imported native release candidate.

This is a **build-time official source dependency**, not a claim that SwiftPM consumes npm packages or that the published npm API exposes every native requirement. The native bridge still needs private source readiness, ordered UTF-16 transport, captured action provenance, safe serialization and bounded-host adapters. These are explicitly documented in `Tools/Core/adaptations.json` and the standalone patch. No parser is reimplemented in Swift, no React UI is shipped, and app launch never fetches JavaScript from a service.

The upstream revision, signature patch, native adapter revision and generated resource hash are independent provenance fields. Changing any of them requires the existing differential/golden tests; never regenerate those fixtures merely to hide a mismatch. Resource generators for the catalog, citations and icons use their own immutable upstream revisions, rather than requiring the deleted monorepo history to exist locally.

Normal consumers need Xcode/SwiftPM and the committed resources only. Node/npm/Git are maintainer tools. The three presentation-tool locks now use public `registry.npmjs.org` URLs with unchanged package integrity digests; internal registry access is not required.

## Verification

Run from the repository root on a Mac with the supported Xcode toolchain:

```sh
python3 Tools/check_openui_integration.py
python3 Tools/check_module_boundaries.py
npm ci --prefix OpenUI/Tools/Core --ignore-scripts
node OpenUI/Tools/Core/build.mjs
node OpenUI/Tools/Core/verify-compatibility.mjs
node --test OpenUI/Validation/validation.test.mjs
# Bundle content must remain exactly the imported hash for this migration.
git diff --exit-code -- Sources/OpenUILang/Resources
swift test
python3 Tools/check_product_consumers.py --scratch-root /tmp/openui-consumers
swift test -c release --filter 'HostSizingIsolationTests|CoreHostIsolationTests'
swift run IntelligentUIGallery --validate-fixtures
python3 Tools/check_lang_compatibility.py
```

`OpenUI/Tools/Core/verify-native.sh` retains general-library golden-contract checks, language ASan and platform compilation using the root package. Historical Intelligent UI contracts still compare against `ed3f6f82abf6f7cc9e307e9bb2eb21073a1f7d79`; source relocation is not an excuse to replace that baseline.

The current branch refactors Swift ownership without changing the Lang contract. The [native workflow](../.github/workflows/native-sdk.yml) records checks for each commit; these commands and the module graph do not imply that every Apple-native gate has passed.

`OPENUI_SNAPSHOT_DIR` enables native visual/measurement exports. A generated PNG, syntax check or successful compile is not an iOS runtime/interaction sign-off. The migration has no automatic release step. The existing public `0.1.1-rc.20` and source integration branch remain intact; RC21 is a separate gate on an explicitly reviewed SHA.

## Maintenance rules

1. Keep the runtime neutral: no chat list, payments, navigation database or business vocabulary in these targets.
2. Keep one source owner per native module under root `Sources/`. Shared runtime behavior belongs in Core; each UI library owns its own component and visual policy.
3. Keep layout measurements free of semantic source submission and business effects.
4. Keep individual subscriptions cancelable even when their underlying resource work is shared.
5. Keep MarkdownUI 2.4.1, Lucide artwork, SF Symbols for internal actions, MapKit, native Canvas charts and existing formula backend for this relocation. Dependency replacement is not bundled into a file move.
6. Prefer improving the source-owned feature over adding a parallel runtime or global cache. Existing tests and component contracts travel with their implementation.
