# OpenUI Swift review and workspace integration

## Scope and version identity

Reviewed import: `zyfn/openui@f3dfa1d0b479c131b6d4268e81961186f22ff09c`, including the first implementation batch, integration with main, D1–D5 corrections and POI/quiet-image presentation. Target base: `zyfn/open-intelligent-ui-swift` branch `codex/intelligentui-design-revamp`, commit `a9099441a8b912a76bae7d4bd7eab0e50859749d`. Work happens only on `codex/swift-sdk-consolidation-rc21`; neither original target branch nor either repository's main is replaced.

This record separates source review, engineering test results and native/device acceptance. The independent user acceptance report belongs to `2308c31`, not the import head; its 571-test pass and five defects must not be described as final-head verification. The source `9baba3c` workflow passed all engineering stages; both inspected `f3dfa1d` native attempts were cancelled before any test steps. There is no RC21 publication based on a cancelled or missing native result.

## Changes by ownership

| Area | Changes retained from the implementation branch | Architectural review |
| --- | --- | --- |
| Language bridge and budgets | UTF-16-identical replay suppression, true append dispatch, total-source/expression budgets, last-good result on rejection | Correct owner: Swift transport around the shared core. It is not a new Swift parser. Source limits change excessive-input behavior and must remain documented. |
| Document state and actions | Source vs presentation identity, submitted value flushing, invalid draft blocking, document-owned drafts, source conflicts, error order and reveal, stale callback rejection | Keep `OpenUIState` as facade and the existing Store authoritative. Do not move chat sessions or scrolling into it. |
| Rendering and layout | Live lookup buckets, redundant empty publication suppression, Pager/table/Flex/card equivalent reductions, read-only repeated fitting, renderer-helper consolidation | Local optimizations retain existing identity and geometry. They are not a claim that no ancestor body/layout runs or that the evaluator is fully incremental. |
| Rich text | Text-feature grouping, precise code copying, presentation coalescing, serialized preparation with one latest replacement, reusable prepared content | MarkdownUI remains the default. OpenUI DSL parsing and field Markdown parsing are different responsibilities; full-prefix Markdown cost still exists. |
| Resources | Bounded response bodies, decoding admission and downsampling, permission scopes, independent subscriber cancellation, failure/termination handling | Download, decode, cache and externally retained images are different budgets. A 32 MiB cache does not bound total process memory. |
| Formula and SVG | Constrained markup, complexity/viewports, explicit final states, math font/layout barriers and identity-safe host teardown | Preserve a restricted native adapter, not a generic web execution environment. Intermittent formula and device reentry need evidence in the exact native build. |
| Data, controls and visual behavior | Missing/invalid chart values not converted to zero, precision, timezone/calendar scope, RTL chart/Slider coordinates, single field feedback | Data association and submit semantics take priority over cosmetic symmetry. D1–D5 have dedicated regressions. |
| Image presentation | Map preview uses a location badge without a photo; failed ordinary images fade without error copy | Geometry is intentionally retained to avoid text reflow. Transparent space is not the same as collapsing an image slot. |
| SDK contracts | Metadata extension through existing component registration, separate reader/writer and standard catalogs, no added model components | Keep original argument order and exported schemas. Do not replace Intelligent UI's catalog with the standard 87-component reference catalog. |
| Tests/CI | Native regression, ASan, platform builds, real-host fitting, screenshots, cancellation tests and provenance | Source/syntax checks are not Apple SDK execution; screenshots must be inspected, not only generated. |

## Maintenance findings resolved by this migration

1. **Whole-fork dependency:** the target package and its Gallery separately resolved the old public fork. They now use one committed set of root native targets. Runtime code and generated resources are imported byte-for-byte, except generated provenance metadata.
2. **Hidden monorepo source/history dependency:** core, catalog, citation and icon generators previously read sibling TypeScript directories or `git show` historical upstream files from the fork. `OpenUI/Tools/upstream.json` now owns immutable official revisions. The build helper verifies the original and adapted core trees and the explicit signature patch before generation. It fetches source only for maintainer builds.
3. **Internal npm registry:** three presentation-generator lockfiles used `registry.anpm.alibaba-inc.com`. URL origins are changed to public npm; versions and integrity fields are retained. Rebuilding each resource must prove that the output did not drift.
4. **Two runtime resolutions:** root and Gallery locks/package references could diverge. The Gallery now uses the same root package; only one module of each native product is built.
5. **Fixture and example path coupling:** original tests assumed `packages/swift-*` / `spec/fixtures`. Their lookup paths are relocated with the same fixtures and assertions. Standard examples compile against the root products. Historic reader-contract verification still uses its original baseline.
6. **Licensing and history:** keep upstream license, generated dependency notices, source commit, import mapping and per-file hashes. Do not merge the entire TypeScript fork's history into this native repository. The source fork remains available for old consumers and release compatibility.

## Dependency decision

SwiftPM cannot directly substitute a TypeScript npm package for `OpenUILang`. The official core's public npm exports do not provide all the private metadata and helpers used by this bridge. Removing those adapters would discard tested native semantics.

The adopted boundary is therefore **official pinned source at build time + explicitly maintained native adapters + committed JavaScriptCore resource**, not a runtime WebView and not a separate native parser. The original byte-preserving relocation retained runtime hash `10227f1773ec35d0cadee6937cb5f1ca93eb04461d3885cd78d9074c9cbb24af`. The subsequent RC21 dependency-security update intentionally rebuilds it; its new provenance and compatibility evidence are recorded in releases/0.1.1-rc.21.md.

The repository retains two composition libraries. `OpenUISwiftUI` owns the general standard library; `SwiftIntelligentUI` owns its existing catalog, design system and generated contract. Share language/state/renderer mechanisms, not incompatible component definitions or visual policies. No new cross-cutting manager, parallel Store, dynamic engine router or chat framework is introduced.

## Acceptance and release decision

Local checks cover manifest structure, source identity, generator syntax, authoring/localization and Swift syntax. The new branch's CI must additionally rebuild pinned core and presentation resources, run the independent oracle, run both native test suites, compare all 61 historical Intelligent UI reader entries, compile both examples and iOS, and run language ASan and Release fitting.

The public source RC21 and this private workspace migration are independent decisions. A green old source build does not certify this new package arrangement; a successful migration input check does not authorize release. A release requires a fixed SHA with valid engineering results and explicit supported behavior. Do not silently publish the private target, alter visibility, move existing tags or delete the public package.

The user-report gaps remain scoped: iOS runtime/touch, real IME, effective accessibility sizing, complete VoiceOver and all component states were not established by the original report. These are not erased by relocation. No zero-bug, all-53-tasks-closed or all-87-component-states claim is made.

## Release blocker found during this review (resolved for RC21)

**Historical blocker at the import candidate: do not publish without repairing the dependency.** An actual `npm audit` on the locked Core generator dependency graph reports `zod@4.4.3` as affected by `GHSA-mrhx-c7xc-m3w5` (high severity, collection-validation resource exhaustion; patched versions start at 4.6.6). Zod is bundled into `lang-core.js` and is used by the authoring bridge, so it must not be dismissed as an irrelevant development-only dependency. Existing source budgets are defense in depth, not a proven exclusion of every schema-validation path. No claim of remote exploitability or data disclosure is made by this dependency finding alone.

Reference: https://github.com/advisories/GHSA-mrhx-c7xc-m3w5 . The captured audit is from private input-verification run `43507589072`; its artifact SHA-256 is `9bd67405276dcaf7d5157df94dc107a396d4e2dcbf1daea2539f617017542c3f`. The dependency versions are deliberately unchanged in this byte-preserving relocation. Fixing the dependency is a separate functional update: pin a patched version, regenerate the runtime and notices, review schema/fixture differences, and run both Apple-native contracts and the upstream oracle before release. The added independent dependency-security CI job is an enforced gate, not a waived warning.

## Completed migration-specific verification

Run `43507589072` materialized and checked the complete reviewed workspace tree before push. It rebuilt the core from the pinned official repository (including its TypeScript configuration and bridge module-type metadata), preserving runtime SHA-256 `10227f1773ec35d0cadee6937cb5f1ca93eb04461d3885cd78d9074c9cbb24af`. The official oracle reports 51 strict parser comparisons, 5 action traces, 4 controlled query snapshots, 6 serializer roundtrips and zero unexplained differences. Six authoring tests and localization/import ownership checks also passed. Earlier generator-layout failures were diagnosed and retained; the runtime baseline was not regenerated to hide them.

Local Swift source parsing and the Foundation-only architecture harness are additional checks, not Apple SDK typechecking. Full two-library native CI, Gallery builds and device/UI acceptance remain separate gates at the final migration commit. The dependency finding was subsequently repaired for RC21 by pinning Core Zod 4.6.6, rebuilding the resource, retaining schema/signature compatibility, and auditing the locked graphs. See releases/0.1.1-rc.21.md for current verification and remaining limits.
