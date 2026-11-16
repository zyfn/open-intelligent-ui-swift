// SwiftLang — Recursive render node.
//
// Renders a single EvaluatedElement by looking up its component in the
// registry and recursively rendering its children.

import SwiftUI

/// Registry: component typeName → SwiftUI view builder.
///
/// The renderer has NO built-in components (like react-ui is separate from
/// react-lang). Apps register their own components here.
public struct OpenUIComponentRegistry: ExpressibleByDictionaryLiteral {
    public typealias Builder = (EvaluatedElement, OpenUIComponentRegistry) -> AnyView
    private var builders: [String: Builder]
    private var presentationPlaceholders = Set<String>()
    private var layoutFields: [String: [String]] = [:]
    private var formControlLabelOwners = Set<String>()
    private var identityProperties: [String: [String]] = [:]
    private var placeholderProperties: [String: [String]] = [:]
    private var revision = NativeRegistryRevision()
    var renderRevision: ObjectIdentifier { ObjectIdentifier(revision) }

    public init(_ builders: [String: Builder] = [:]) { self.builders = builders }
    public init(dictionaryLiteral elements: (String, Builder)...) {
        builders = Dictionary(elements, uniquingKeysWith: { _, latest in latest })
    }
    public subscript(_ name: String) -> Builder? {
        get { builders[name] }
        set {
            revision = NativeRegistryRevision()
            builders[name] = newValue
            presentationPlaceholders.remove(name)
            layoutFields.removeValue(forKey: name)
            formControlLabelOwners.remove(name)
            identityProperties.removeValue(forKey: name)
            placeholderProperties.removeValue(forKey: name)
        }
    }
    package mutating func setPresentationPlaceholder(_ name: String, enabled: Bool) {
        revision = NativeRegistryRevision()
        if enabled { presentationPlaceholders.insert(name) }
        else { presentationPlaceholders.remove(name) }
    }
    package func supportsPresentationPlaceholder(_ name: String) -> Bool { presentationPlaceholders.contains(name) }
    package mutating func setLayoutFields(_ name: String, fields: [String]) {
        revision = NativeRegistryRevision(); layoutFields[name] = fields
    }
    package func presentationLayoutFields(_ name: String) -> [String] { layoutFields[name] ?? [] }
    package mutating func setFormControlLabelOwner(_ name: String, enabled: Bool) {
        revision = NativeRegistryRevision()
        if enabled { formControlLabelOwners.insert(name) }
        else { formControlLabelOwners.remove(name) }
    }
    package func ownsFormControlLabel(_ name: String) -> Bool { formControlLabelOwners.contains(name) }
    package mutating func setIdentityFields(_ name: String, fields: [String]?) {
        revision = NativeRegistryRevision()
        identityProperties[name] = fields
    }
    /// Identity belongs to the supplied component library, including when two
    /// libraries use the same component name with different parameter meanings.
    public func identityFields(for name: String) -> [String] {
        identityProperties[name] ?? ["key", "id", "resourceId"]
    }
    package mutating func setPlaceholderFields(_ name: String, fields: [String]) {
        revision = NativeRegistryRevision()
        placeholderProperties[name] = fields
    }
    package func presentationPlaceholderFields(_ name: String) -> [String] {
        placeholderProperties[name] ?? []
    }
}

private final class NativeRegistryRevision {}

/// Recursively renders an `EvaluatedElement` tree.
public struct RenderNode: View {
    private let element: EvaluatedElement
    private let registry: OpenUIComponentRegistry

    public init(element: EvaluatedElement, registry: OpenUIComponentRegistry) {
        self.element = element
        self.registry = registry
    }

    public var body: some View {
        NativeRenderedNode(element: element, registry: registry).equatable()
    }
}

/// Environment changes and component-local observation still reach descendants.
/// This boundary filters only unchanged inputs supplied by a parent render.
private struct NativeRenderedNode: View, Equatable {
    let element: EvaluatedElement
    let registry: OpenUIComponentRegistry

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.registry.renderRevision == rhs.registry.renderRevision
            && nativePresentationInputsEqual(lhs.element, rhs.element)
    }

    var body: some View {
        ElementErrorBoundary(element: registry[element.typeName] == nil ? nil : element) { el in
            if let builder = registry[el.typeName] {
                builder(el, registry)
            } else {
                // Unknown component: render nothing (upstream drops it).
                EmptyView()
            }
        }
    }
}

/// Helpers for building component views from EvaluatedElement props.
public enum PropValue {
    /// Get a string prop, or nil.
    public static func string(_ el: EvaluatedElement, _ key: String) -> String? {
        guard let v = el.props.first(where: { $0.0 == key })?.1 else { return nil }
        if case .string(let s) = v { return s.displayString }
        return nil
    }

    /// Get child elements from an array prop (e.g. "children").
    public static func children(_ el: EvaluatedElement, _ key: String = "children") -> [EvaluatedElement] {
        guard let v = el.props.first(where: { $0.0 == key })?.1 else { return [] }
        if case .array(let items) = v {
            return items.compactMap { item in
                if case .element(let e) = item { return e }
                return nil
            }
        }
        if case .element(let e) = v { return [e] }
        return []
    }

    /// Get an action plan prop (e.g. Button's "action").
    public static func actionPlan(_ el: EvaluatedElement, _ key: String) -> ActionPlan? {
        guard let v = el.props.first(where: { $0.0 == key })?.1 else { return nil }
        if case .actionPlan(let plan) = v { return plan }
        return nil
    }
}

extension PropValue {
    /// Use for semantic operations; string() is a display-only native bridge.
    public static func codeUnitString(_ element: EvaluatedElement, _ key: String) -> OpenUIString? {
        guard case .string(let value) = value(element, key) else { return nil }; return value
    }
}


// MARK: - RenderValue

/// The framework adapter's recursive child renderer. Containers may pass any
/// child value here, including a scalar or nested array returned by @Each.
public struct RenderValue: View {
    private let value: Value
    private let registry: OpenUIComponentRegistry
    public init(_ value: Value, registry: OpenUIComponentRegistry) {
        self.value = value; self.registry = registry
    }
    public var body: some View {
        switch value {
        case .element(let element): RenderNode(element: element, registry: registry)
        case .string(let text): Text(text.displayString)
        case .number(let number): Text(jsNumberString(number))
        case .boolean(let flag): Text(flag ? "true" : "false")
        case .array(let values):
            ForEach(OpenUIRenderChild.children(of: .array(values), registry: registry)) { child in
                RenderValue(child.value, registry: registry)
            }
        default: EmptyView()
        }
    }
}

extension PropValue {
    public static func value(_ element: EvaluatedElement, _ key: String) -> Value? {
        element.props.last(where: { $0.0 == key })?.1
    }
}


// MARK: - RenderIdentity

/// Identity for a rendered child. Dynamic stateful content should declare a
/// runtime statement id or a key/id already supported by its schema.
public struct OpenUIRenderChild: Identifiable {
    public let id: String
    public let value: Value

    public init(id: String, value: Value) {
        self.id = id
        self.value = value
    }

    public static func children(of value: Value, registry: OpenUIComponentRegistry? = nil) -> [OpenUIRenderChild] {
        func flattened(_ value: Value, path: String) -> [(String, Value)] {
            if case .array(let items) = value {
                return items.enumerated().flatMap { flattened($0.element, path: path + "." + String($0.offset)) }
            }
            if case .null = value { return [] }
            if case .undefined = value { return [] }
            return [(path, value)]
        }
        var occurrences: [String: Int] = [:]
        return flattened(value, path: "root").map { position, value in
            let base: String
            if case .element(let element) = value {
                let identityProps = registry?.identityFields(for: element.typeName) ?? ["key", "id", "resourceId"]
                let key = identityProps.lazy.compactMap { name -> String? in
                    guard let value = element.props.last(where: { $0.0 == name })?.1 else { return nil }
                    switch value {
                    // ASCII encoding keeps canonical Unicode variants and
                    // isolated UTF-16 units distinct in Swift String IDs.
                    case .string(let key) where !key.isEmpty:
                        return "u:" + key.codeUnits.map { String($0, radix: 16) }.joined(separator: ".")
                    case .number(let key) where key.isFinite: return "n:" + jsNumberString(key)
                    default: return nil
                    }
                }.first
                if let key { base = "key:\(element.typeName):\(key)" }
                else if let statement = element.statementId { base = "statement:\(statement)" }
                else { base = "anonymous:\(element.typeName):\(position)" }
            } else { base = "scalar:\(position)" }
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            return OpenUIRenderChild(id: base + ":" + String(occurrence), value: value)
        }
    }
}


// MARK: - ErrorBoundary

// SwiftLang — Error boundary.
//
// Swift port of react-lang's `ElementErrorBoundary`. Keeps the last
// registered element; if the input becomes unavailable, the last good
// version is shown. This does not catch SwiftUI runtime crashes.


/// A view that keeps the last successful render when its input becomes unavailable.
///
/// SwiftUI has no try/catch around view builders, so this boundary works at
/// the element level: it stores the last `EvaluatedElement` that rendered
/// without the registry reporting an error, and falls back to it when the
/// current element has no registered component.
public struct ElementErrorBoundary<Content: View>: View {
    private let input: NativeBoundaryInput
    private let content: (EvaluatedElement) -> Content
    @StateObject private var lastGood = NativeBoundarySnapshot()

    public init(
        element: EvaluatedElement?,
        @ViewBuilder content: @escaping (EvaluatedElement) -> Content
    ) {
        self.input = NativeBoundaryInput(element: element)
        self.content = content
    }

    public var body: some View {
        Group {
            if let shown = input.element ?? lastGood.element {
                content(shown)
            } else {
                EmptyView()
            }
        }
        .onAppear { if let element = input.element { lastGood.element = element } }
        .onChange(of: input) { if let element = $0.element { lastGood.element = element } }
    }
}

/// Snapshot identity includes readiness-only replacements without invoking
/// EvaluatedElement's structural language-value equality on every render.
private struct NativeBoundaryInput: Equatable {
    let element: EvaluatedElement?
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.element === rhs.element }
}

/// Input changes already invalidate the boundary. Retaining its last successful
/// input must not publish a second update; StateObject only owns this lifetime.
private final class NativeBoundarySnapshot: ObservableObject {
    var element: EvaluatedElement?
}
