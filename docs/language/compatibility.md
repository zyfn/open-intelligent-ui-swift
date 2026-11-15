# Native compatibility contract

The official commit, original core tree and adapted core tree are pinned in
[core-manifest.json](../../Sources/OpenUILang/Resources/core-manifest.json) and
[the source lock](../../Tools/upstream.json). The positional-omittability patch
is applied to the frozen official source with its exact SHA-256 and tree checked.
`Tools/Core/build.mjs` then performs the recorded platform and dependency
adaptations; the generated Apple bundle is an adapted build.

`Tools/Core/adaptations.json` is the maintained inventory. Each item identifies its
category, location, reason, observable effect, verification and removal condition.
The build embeds the complete inventory, including readiness injection, in the
manifest and hashes the adapter inputs and standalone serializer patch.
The four SDK products share one language implementation and the official
DSL/schema/action wire vocabulary. Platform budgets are explicit exceptions to
stock-core equivalence.

## Current language version and reference documents

The SDK runs the pinned official `@openuidev/lang-core` **1.1.1** with the native
adaptations recorded above. [Overview](overview.md), [Language](language.md)
and [Prompt](prompt.md) retain the **1.0 reference specification**, alongside
the versioned [1.0 fixtures](../../Fixtures/Language/1.0/README.md). Their version
label identifies that reference, not the version of the bundled runtime.

For model input, use the selected library's current `systemPrompt` and
`specificationJSON`. They describe its actual component catalog, functions and
generation policy. The key 1.1.1 runtime behavior relevant to those older
reference documents is:

| Area | Current behavior |
| --- | --- |
| Query dependencies | State dependencies are tracked through referenced statements and aliases. A query that reads another query waits for its upstream result and reevaluates when that dependency changes. The 1.0 direct-state-only description does not apply. |
| Query failures and cycles | Repeated evaluation with unchanged inputs does not automatically retry a failed query; explicit `@Run` or host invalidation can retry it. Query cycles report `query-cycle` and do not dispatch their tools. |
| State defaults | Expressions can compute an initial default. Separate statements `$n = 2` and `$total = $n * 3` initialize `$total` to 6; later writes to `$n` do not make that default a reactive formula. Derived values belong in ordinary variables. |
| Numeric built-ins | `@Round`, `@Abs`, `@Floor` and `@Ceil` also accept arrays and apply their operation element by element. The 1.0 scalar-only signature table is incomplete for the current runtime. |

The first-class cases in [lang-1.1-regressions.mjs](../../Tools/Core/lang-1.1-regressions.mjs)
compare these outcomes with the pristine pinned official implementation and the
actual bundled resource. [Lang111Tests.swift](../../Tests/OpenUILangTests/Lang111Tests.swift)
and the query lifecycle tests cover the native bridge. Updating reference
material or generating a fixture does not establish that those checks ran.

## Authoring and compatible schema edits

Prefer `Library.extend(...)` followed by `toSchema()` for structural authoring.
Compiled schema projections remain mutable for source compatibility. Their
setters synchronize the retained full ordered JSON Schema, rather than dropping
it or merely clearing a prepared-library cache. Unmodified shared definitions,
references, annotations and constraints stay intact. Binding metadata remains
native. A copy owns its edits and its newly prepared library independently.

Component removal updates component membership; an unregistered `$defs` entry
may remain as a shared data reference. Reordering parameters changes only their
positional property order. Built-in language definitions remain upstream-owned.
This compatibility path adds no competing schema compiler or authoring rules.

## Reproducible checks

Run from the SDK root on a supported Apple host:

```sh
npm ci --prefix Tools/Core --ignore-scripts
node Tools/Core/build.mjs
node Tools/Core/verify-compatibility.mjs
swift test --filter OpenUILangTests
```

The verifier builds the pinned official core without Swift patches or readiness
plugins. Upstream telemetry source is retained and its opt-in remains disabled.
It compares every protocol field and ordering in the selected batch, truncated
and intermediate streaming results, complete and replacement results. It does
not discard errors, sort unresolved names or rewrite expected diagnostics.
Only the explicitly named native source-metadata Symbols are omitted; WeakMap
metadata never appears in protocol values.

The checked-in strict fixture is generated with `--write` only after reviewing
an upstream/contract change. Swift tests compare actual parser-facade snapshots
and every typed diagnostic against this independent fixture. Five native action
traces compare events, state and controlled tool calls with the exact pinned
official framework callback, executed with injected host dependencies. It is
the real callback source, not a second handwritten reference interpreter.
Success, failure and cancellation are distinct cases.

The Node verifier also compares four controlled query snapshots, including
disposal with a late result, between official and bundled core managers.
Swift QueryLifecycleTests independently cover native callback replacement and
disposal. This does not claim a live-network, mounted React-versus-SwiftUI test.

Six serializer regressions are kept separate from byte-for-byte equivalence:
the corrected output must parse on the unmodified official parser and preserve
computed meaning. The independent local patch in `Tools/Core/patches` must apply
and produce exactly the build transformation. No upstream submission is implied.

## Readiness and diagnostics

Readiness still injects hooks into lexer, expressions, parser, materializer,
evaluator and evaluate-tree. The pinned upstream API does not expose equivalent
source/dependency provenance. Parser-owned Symbols and evaluated-value WeakMaps
remain side channels; they do not add protocol fields, persisted state or action
parameters. UI regressions verify complete controls can execute while unrelated
text streams, incomplete actions remain blocked, and replacement invalidates old
callbacks. Source injection is deliberately retained until an equivalent API is
verified; moving files would not remove that coupling.

Some official diagnostics omit `source`. The native API's existing nonoptional
`source` property retains its parser display fallback for source compatibility.
The additive `protocolSource` property preserves actual source presence, and
strict raw/typed tests verify the omission rather than inventing a wire field.
No diagnostic code or DSL construct is added.

## Resource limits and verification boundary

- Source: 128 nested delimiter levels or 256 operators per expression. Exceeding
  these reports the existing `parse-exception` diagnostic.
- Materialization: 256 recursive levels / 100000 nodes; exhaustion reports the
  existing `parse-exception`. Limit tests are separate from equivalence fixtures.
- Ordered JSON decoding: 128 levels, with a native JSON error on exhaustion.
- Pattern execution: 65536 UTF16 pattern units, 1048576 input units, bounded
  memory, stack and VM interruptions. Exhaustion blocks form submission with
  `Validation could not complete: regular expression resource limit exceeded.`
  Ordinary mismatch remains `Invalid format`; invalid pattern keeps official
  lenient behavior. The public DSL error vocabulary is not expanded.
- Native value conversion retains a defensive 256-level decoding guard. Values
  needing deeper transport remain explicitly outside this verified domain;
  their conversion behavior is recorded as unproven in the inventory. This
  patch does not claim arbitrary-depth transport or a universal execution budget.

Within these bounds, all maintained reference and strict trace cases must pass.
Passing finite fixtures is regression evidence, not a proof about every program,
future core release, backend, device or network schedule. New differences must
be explained or repaired before changing a checked-in expectation.

## Native controls

EditableTable commits through the component context using the same revision,
readiness and activation gates as standard controls. Its local delivery receipt
is independent of the returned event list and does not acknowledge remote
persistence. Store publication cannot commit a rejected local draft; replacement
starts a new draft lifetime. Tests cover the coordinator and a mounted native
view's real source observation.

Slider's lattice uses the precision of minimum and step for both choices and
dragging. Fractional-origin rounding is an explicit repair of an upstream UI
defect. On non-divisible ranges, the dragged value may clamp to the maximum;
the discrete list includes complete steps. Continuous text input still accepts
off-step numeric drafts and validates their range, as in the reference wrapper.
