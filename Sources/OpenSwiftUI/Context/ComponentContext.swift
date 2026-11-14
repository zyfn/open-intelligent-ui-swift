import SwiftUI
import OpenUILang
import OpenUICore

private enum StandardThemeContextKey: OpenUIContextKey {
    static let defaultValue = OpenUIThemeValues.defaults
}
private enum StandardPresentationContextKey: OpenUIContextKey {
    static let defaultValue = OpenUIPresentation.defaults
}
private enum StandardStretchHeightContextKey: OpenUIContextKey {
    static let defaultValue = false
}
private enum StandardFillControlWidthContextKey: OpenUIContextKey {
    static let defaultValue = false
}

extension OpenUIContextValues {
    public var standardTheme: OpenUIThemeValues {
        get { self[StandardThemeContextKey.self] }
        set { self[StandardThemeContextKey.self] = newValue }
    }
    public var standardPresentation: OpenUIPresentation {
        get { self[StandardPresentationContextKey.self] }
        set { self[StandardPresentationContextKey.self] = newValue }
    }
}

/// Standard-library presentation extends the shared runtime context.
extension OpenUIComponentContext {
    public var theme: OpenUIThemeValues { values.standardTheme }
    public var presentation: OpenUIPresentation { values.standardPresentation }

    // A one-level proposal consumed at a standard component boundary.
    var stretchesVertically: Bool {
        get { values[StandardStretchHeightContextKey.self] }
        set { values[StandardStretchHeightContextKey.self] = newValue }
    }
    var fillsControlWidth: Bool {
        get { values[StandardFillControlWidthContextKey.self] }
        set { values[StandardFillControlWidthContextKey.self] = newValue }
    }

    /// Keeps the standard-library initializer available while a Core-only
    /// caller can construct the same context without a standard design system.
    @MainActor @_disfavoredOverload
    public init(element: EvaluatedElement, registry: OpenUIComponentRegistry, state: OpenUIState,
                theme: OpenUIThemeValues = OpenUIThemeValues(),
                presentation: OpenUIPresentation = OpenUIPresentation(),
                resources: [String: Value] = [:], formName: String? = nil, exactFormName: OpenUIString? = nil) {
        var values = OpenUIContextValues()
        values.standardTheme = theme
        values.standardPresentation = presentation
        self.init(element: element, registry: registry, state: state, values: values,
                  resources: resources, formName: formName, exactFormName: exactFormName)
    }

    func renderTableCell(_ value: Value, policy: OpenUITableCellPolicy) -> RenderValue {
        RenderValue(value, registry: NativeTableCellContent.registry(from: registry, policy: policy))
    }
    func presentationChildren(_ name: String = "children") -> [OpenUIRenderChild] {
        NativePresentationProxy.children(value(name) ?? .null, source: element.sourceReadiness[name], registry: registry)
    }
    var layoutConfigurationReady: Bool {
        NativeLayoutContract.ready(element.sourceReadiness, fields: registry.presentationLayoutFields(element.typeName))
    }
    var rowWidthReady: Bool {
        NativeLayoutContract.rowWidthReady(value("children") ?? .null,
            source: element.sourceReadiness["children"], registry: registry)
    }
    func presentationValue(_ name: String = "children") -> Value {
        NativePresentationProxy.expandedValue(value(name) ?? .null, source: element.sourceReadiness[name], registry: registry)
    }
    func componentOwnsFormControlLabel(_ name: String) -> Bool {
        registry.ownsFormControlLabel(name)
    }
}

/// Applies only the standard component library's visual and layout policy.
/// The enclosing Core host already owns session scope and resource lifetime.
struct NativeComponentHost<Content: View>: View {
    let context: OpenUIComponentContext
    let content: (OpenUIComponentContext) -> Content
    @Environment(\.openUITheme) private var theme
    @Environment(\.openUIPresentation) private var presentation
    @Environment(\.openUIStretchHeight) private var stretchesVertically
    @Environment(\.openUIFillControlWidth) private var fillsControlWidth

    init(context: OpenUIComponentContext,
         @ViewBuilder content: @escaping (OpenUIComponentContext) -> Content) {
        self.context = context
        self.content = content
    }

    var body: some View {
        // Only inheritable library values continue down the tree. The current
        // row/control proposal belongs to this boundary and is consumed here.
        var scopedValues = context.values
        scopedValues.standardTheme = theme
        scopedValues.standardPresentation = presentation
        var context = context
        context.values = scopedValues
        context.stretchesVertically = stretchesVertically
        context.fillsControlWidth = fillsControlWidth
        let element = context.element
        let atomic = ["Card", "Form", "CompositeCardItem", "VisualCardItem", "ContextCardItem", "OverviewCardItem", "SnippetCardItem"].contains(element.typeName)
        let presented = Group {
            if !context.layoutConfigurationReady && element.typeName != "Stack" && element.typeName != "Card" {
                NativePendingContent(loading: !context.hasDataFailure && (context.isStreaming || context.hasPendingData),
                    terminalMessage: context.hasDataFailure ? "Content unavailable" : "Content is incomplete")
            } else if context.registry.supportsPresentationPlaceholder(element.typeName),
               let field = NativePresentationProxy.primaryTextField(element.typeName),
               element.sourceReadiness.placeholder != nil || context.codeUnitString(field) == nil {
                NativeTextPlaceholder(context: context)
            } else { content(context) }
        }
        return presented.environment(\.openUIStretchHeight, false)
            .environment(\.openUIFillControlWidth, false)
            .environment(\.openUIInteractionScopeReady,
                context.interactionScopeReady && (!atomic || context.canInteract))
            .environment(\.openUIInlineLinksReady, context.canInteract)
            .environment(\.openUIMediaSourceReady,
                ["Image", "ImageBlock", "ImageText", "ImageTextLarge"].contains(element.typeName)
                    ? element.sourceReadiness["src"].complete : element.isSourceComplete)
            .environment(\.openUIStreamActive, context.isStreaming)
            .allowsHitTesting(element.sourceReadiness.placeholder == nil)
    }
}

