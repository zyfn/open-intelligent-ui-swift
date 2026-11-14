import SwiftUI

/// A typed extension point for a component library's context values.
/// Defaults should be stable values; use `nil` when no value was supplied.
public protocol OpenUIContextKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

/// Values travel with the component context without coupling the shared
/// runtime to a particular component library, theme, or presentation system.
public struct OpenUIContextValues {
    private var storage: [ObjectIdentifier: Any] = [:]

    public init() {}

    public subscript<Key: OpenUIContextKey>(_ key: Key.Type) -> Key.Value {
        get { storage[ObjectIdentifier(key)] as? Key.Value ?? Key.defaultValue }
        set { storage[ObjectIdentifier(key)] = newValue as Any }
    }
}

private struct OpenUIContextValuesKey: EnvironmentKey {
    static let defaultValue = OpenUIContextValues()
}

extension EnvironmentValues {
    public var openUIContextValues: OpenUIContextValues {
        get { self[OpenUIContextValuesKey.self] }
        set { self[OpenUIContextValuesKey.self] = newValue }
    }
}

extension View {
    public func openUIContextValues(_ values: OpenUIContextValues) -> some View {
        environment(\.openUIContextValues, values)
    }
}
