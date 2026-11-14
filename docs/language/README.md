# OpenUILang

Apple-platform bindings for the shared OpenUI `lang-core`. The SwiftPM product and
import are `OpenUILang`, built by the repository-root `OpenUISwiftSDK` package.
Swift 6 tools build in Swift 5 language mode on iOS 16+ and macOS 13+.
JavaScriptCore is required.

The bundled language implementation is based on official
`@openuidev/lang-core` **1.1.1**, pinned to an exact source commit and combined
with the recorded Apple-platform bridge and compatibility adaptations.

Parsing, streaming completion, expression evaluation, library extension, Schema,
Prompt generation, Store, query lifecycle and message handling delegate to the
pinned shared core. Native code supplies typed values, lossless UTF-16 transport,
async tools, cancellation and host action execution. There is no Linux fallback.

## Installation

The repository-root `Package.swift` exports `OpenUILang`, `OpenUICore`,
`OpenSwiftUI` and `OpenIntelligentSwiftUI`. A language-only consumer selects
`OpenUILang`; it does not depend on Core or either UI library and does not import
SwiftUI. Both UI libraries use the same language module through the shared Core
foundation. A consumer that directly uses language APIs and native UI can
explicitly declare both products without creating a second language runtime.
See the [SDK installation and common integration guide](../../README.md).

This directory contains documentation; there is one SDK package at the root.

## Use an exported library

```swift
import OpenUILang

let spec = try LibrarySpec(jsonString: exportedLibrary)
let parser = createParser(schema: compileLibrarySchema(spec))
let result = parser.parse(program)
```

`createParser` returns the `Parser` interface; `createStreamingParser` returns
`StreamParser`. Completion and append/replacement behavior use the shared parser.
`OpenUIString`, `OpenUIArray` and `OpenUIObject` retain JavaScript string and
reference semantics across the native boundary. Concrete JavaScriptCore parser
and Store implementations are internal. `createStore()` returns the core-aligned
`Store` interface, including `getSnapshot`, `subscribe` and `dispose`.

`ParsedMessage` uses the official `content`, `context`, `attributes` and `end`
fields. `context` is parsed JSON or raw text, represented as `JSONValue`; it is
`.null` when absent. `buildMessage` accepts those same fields. The host can retain
its original input separately when exact source bytes are needed.

## Authoring and schema

`DefinedComponent`, `DefinedFunction` and `DefinedAction` follow the core authoring
names. Validation exposes `ParsedRule(type:arg:)` and `ValidatorFn`; `Library.toJSONSchema()`
exports the core schema. Swift definitions and callbacks enter core `defineComponent`, `defineFunction`,
`defineAction`, `createLibrary` and `library.extend` through JSON/Zod transport.
Component reference identity and bindable metadata are preserved. `LibrarySpec`
and signatures come from core `toSpec()`; the adapter does not reproduce an older
Swift schema spelling or custom signature format. JSON Schema integer ranges are
preserved when the Zod importer would otherwise add safe-integer bounds.

## Build and test

```sh
swift test --filter OpenUILangTests
npm ci --prefix Tools/Core --ignore-scripts
node Tools/Core/build.mjs
node Tools/Core/verify-compatibility.mjs
```

Ordinary SwiftPM consumers use the checked-in resource without Node or runtime
downloads. Official `@openuidev/lang-core` 1.1.1 is pinned to commit
`39a4e3f6493673fdf2de04681240374c8d6f6be8`, original core tree
`5c689b8a110471267d35fa40a0f850936c259107` and source-patched tree
`52484f44960dceb33aab0daac8bdf97a5ada1d4b`. The build uses the pinned official
source rather than the npm package's public entry alone. Exact dependency
version, source and shipped-resource hashes live in
[core-manifest.json](../../Sources/OpenUILang/Resources/core-manifest.json).

Compatibility adaptations remain explicit: serializer round-trip grouping and
keys, positional omittability, materialization limits, bounded ECMAScript pattern
execution, native readiness source injection and dependency schema compatibility.
The [source lock](../../Tools/upstream.json) records the official and adapted core
trees and the exact source patch. The adaptation inventory, reasons and removal
gates are embedded in the manifest. See [the compatibility contract](compatibility.md)
for strict oracle checks, native projection rules and resource exceptions. Raw message-context and
legacy output-format compatibility have been removed. A source upgrade must
revalidate the explicit source/build adaptations and reference fixtures.
Third-party licenses ship with the bundle and bounded regex backend.

The 1.1.1 upgrade requires comparison with that pinned version's official parser
and runtime, including expression-based initial state, list/math functions,
query dependencies and retries, streaming, actions and serialization. Older
expected results are not evidence of compatibility when upstream intentionally
changes behavior. Version-specific regressions record those changes separately
from native bridge defects. Generating fixtures or parsing Swift syntax does not
establish successful Apple-platform compilation or test execution.

`Tools/check_product_consumers.py` also builds a separate external consumer that
declares only the `OpenUILang` product and calls authoring, parser and streaming
APIs. It rejects importing Core or either UI library. The source/module-boundary
check independently rejects UI framework imports in Lang; the macOS SDK's
availability of SwiftUI is not itself a package dependency.

A serialized JavaScript realm owns separate parser/Store/query objects. Host
async transport does not hold the realm lock across `await`. Cancellation and
source epochs prevent late responses from updating replacement programs. Typed
native ActionPlans execute at the framework boundary, matching other adapters.

## Language reference

- [Overview](overview.md): the language, streaming and stored UI model.
- [Language specification](language.md): grammar, evaluation, state and actions.
- [Prompt and message protocol](prompt.md): LibrarySpec, generation and stored responses.
- [Conformance fixtures](../../Fixtures/Language/1.0/README.md): versioned examples and expected results.
