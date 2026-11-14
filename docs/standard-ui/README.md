# Standard SwiftUI library

`OpenSwiftUI` supplies the standard OpenUI component library and its native
appearance. It uses the same `OpenUILang` and `OpenUICore` foundation as
`OpenIntelligentSwiftUI`; the two UI libraries remain independently selectable.

Use the common client interface for a complete standard-library document:

```swift
import OpenSwiftUI

let library: OpenUILibrary = try .standard()
let state = library.makeState()
state.setSource(#"root = Stack([TextContent(\"Hello\")])"#)
let view = OpenUIView(state: state, library: library)
```

Create and retain the state on the main actor for the document's lifetime.
The same library exposes `systemPrompt` and `specificationJSON` for generation;
the host owns streaming transport, resources and action routing. See the
[SDK guide](../../README.md) and [module architecture](../architecture.md) for
installation and the shared interface.

## References

| Reference | Scope |
| --- | --- |
| [Component authoring](components.md) | Custom definitions, slots, library extension, theme and presentation APIs |
| [Component catalog](catalog.md) | Pinned standard definitions and native presentation behavior |
| [Layout contract](layout.md) | Measurement, readiness and stable streaming layout |
| [Rendering and verification](design.md) | Visual roles, host responsibilities and acceptance boundaries |
| [Official source mapping](visual-mapping.md) | Pinned reference implementation and explicit native choices |
| [Language guide](../language/README.md) | Shared syntax, schema, action and compatibility contracts |

The standard library includes the 84 pinned upstream definitions plus native
`Map`, `MapPoint` and `SVG` definitions. Export the selected library's actual
contract; the reference catalog alone does not include those native additions.

## Development

Run from the repository root:

```sh
swift test --filter OpenSwiftUITests
npm ci --prefix Tools/Core --ignore-scripts
node Tools/Presentation/catalog.mjs --check
```

The [macOS example](../../Examples/macOS/README.md) is a separate consumer of
the root package. The [Agent cases](../../Examples/AgentCases/README.md) are
versioned contract examples, not live service data or default prompt additions.
