import SwiftUI

private struct OpenUIResourcesKey: EnvironmentKey { static let defaultValue: [String: Value] = [:] }
private struct OpenUIFormKey: EnvironmentKey { static let defaultValue: String? = nil }
private struct OpenUIExactFormNameKey: EnvironmentKey { static let defaultValue: OpenUIString? = nil }
private struct OpenUIProgramScopeKey: EnvironmentKey { static let defaultValue: ObjectIdentifier? = nil }
private struct NativeInteractionScopeKey: EnvironmentKey { static let defaultValue = true }
private struct NativeInlineLinksKey: EnvironmentKey { static let defaultValue = true }
private struct NativeUserInteractionKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }

extension EnvironmentValues {
    package var openUIUserInteraction: (() -> Void)? {
        get { self[NativeUserInteractionKey.self] }
        set { self[NativeUserInteractionKey.self] = newValue }
    }
    package var openUIInteractionScopeReady: Bool {
        get { self[NativeInteractionScopeKey.self] }
        set { self[NativeInteractionScopeKey.self] = newValue }
    }
    package var openUIInlineLinksReady: Bool {
        get { self[NativeInlineLinksKey.self] }
        set { self[NativeInlineLinksKey.self] = newValue }
    }
    public var openUIResources: [String: Value] {
        get { self[OpenUIResourcesKey.self] }
        set { self[OpenUIResourcesKey.self] = newValue }
    }
    public var openUIFormName: String? {
        get { self[OpenUIFormKey.self] }
        set { self[OpenUIFormKey.self] = newValue }
    }
    public var openUIExactFormName: OpenUIString? {
        get { self[OpenUIExactFormNameKey.self] }
        set { self[OpenUIExactFormNameKey.self] = newValue }
    }
    package var openUIProgramScoped: ObjectIdentifier? {
        get { self[OpenUIProgramScopeKey.self] }
        set { self[OpenUIProgramScopeKey.self] = newValue }
    }
}

extension View {
    /// Resources belong to this host/message, not a process-global store.
    public func openUIResources(_ value: [String: Value]) -> some View { environment(\.openUIResources, value) }
    public func openUIForm(_ name: String?) -> some View {
        environment(\.openUIFormName, name).environment(\.openUIExactFormName, name.map { OpenUIString($0) })
    }
}
