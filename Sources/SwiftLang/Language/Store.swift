import Foundation
import JavaScriptCore

/// State semantics are owned by lang-core. Swift retains only the native facade.
final class CoreStore: Store {
    private let core = SharedCore.shared
    private let store: JSValue
    // This ledger contains no business values. It mirrors only the write
    // disposition needed to reject an oversized candidate before JS allocation.
    // The JS Store remains the sole source of values and notifications.
    private struct Entry { let cost: NativeValueCost; let pristine: Bool }
    private struct Ledger {
        var fields: [OpenUIString: Entry] = [:]
        var nodes = 1
        var elements = 0
        var utf16 = 0
        var deepFields = 0
        var exceeds: Bool {
            nodes > NativeValueCost.maximumNodes || elements > NativeValueCost.maximumElements
                || utf16 > NativeValueCost.maximumUTF16 || deepFields > 0
        }
        func rejects(_ name: OpenUIString, cost: NativeValueCost) -> Bool {
            let previous = fields[name]?.cost
            return cost.exceeds || cost.depth + 1 > NativeValueCost.maximumDepth
                || nodes - (previous?.nodes ?? 0) + cost.nodes > NativeValueCost.maximumNodes
                || elements - (previous?.elements ?? 0) + cost.elements > NativeValueCost.maximumElements
                || utf16 - (previous?.utf16 ?? 0) + cost.utf16 + (previous == nil ? name.count : 0) > NativeValueCost.maximumUTF16
        }
        mutating func replace(_ name: OpenUIString, cost: NativeValueCost, pristine: Bool) {
            if let previous = fields[name]?.cost {
                nodes -= previous.nodes; elements -= previous.elements; utf16 -= previous.utf16
                if previous.depth + 1 > NativeValueCost.maximumDepth { deepFields -= 1 }
            } else { utf16 += name.count }
            fields[name] = Entry(cost: cost, pristine: pristine)
            nodes += cost.nodes; elements += cost.elements; utf16 += cost.utf16
            if cost.depth + 1 > NativeValueCost.maximumDepth { deepFields += 1 }
        }
    }
    private final class CachedCost {
        weak var object: AnyObject?
        let cost: NativeValueCost
        init(_ object: AnyObject, cost: NativeValueCost) { self.object = object; self.cost = cost }
    }
    private var ledger = Ledger()
    private var costs: [ObjectIdentifier: CachedCost] = [:]
    private var rejectedMutation = false
    var nativeLimitExceeded: Bool { core.sync { rejectedMutation } }
    private func cost(_ value: Value) -> NativeValueCost {
        guard let object = value.referenceObject else { return nativeValueCost(value) }
        let id = ObjectIdentifier(object)
        if let known = costs[id], known.object === object { return known.cost }
        let measured = nativeValueCost(value)
        if !measured.exceeds {
            if costs.count >= 1_024 { costs.removeAll(keepingCapacity: true) }
            costs[id] = CachedCost(object, cost: measured)
        }
        return measured
    }
    private func defaultCost(_ value: Materialized) -> NativeValueCost {
        switch value {
        case .stateDefault(let value): return cost(value.value)
        case .value(let value): return cost(value)
        default: return nativeMaterializedCost(value)
        }
    }
    public init() { store = SharedCore.shared.sync { SharedCore.shared.call("store") } }
    public func get(_ name: OpenUIString) -> Value? { core.sync {
        let result = core.call("storeRead", [store, core.string(name)])
        guard result.forProperty("found").toBool() else { return nil }
        return core.decode(result.forProperty("value"))
    } }
    public func set(_ name: OpenUIString, value: Value, pristine: Bool) { core.sync {
        let measured = cost(value)
        guard !ledger.rejects(name, cost: measured) else { rejectedMutation = true; return }
        let encoded = core.encode(value)
        // Commit accounting before JS notifies subscribers. A reentrant write
        // must see this accepted write's cost, just as it sees its Store value.
        // Core's SameValue(undefined, absent) is a no-op. Do not invent a
        // field in the ledger: initialize must still see this key as absent.
        if case .undefined = value, ledger.fields[name] == nil {
            // No stored value or accounting entry is created.
        } else {
            ledger.replace(name, cost: measured, pristine: pristine)
        }
        rejectedMutation = false
        _ = store.invokeMethod("set", withArguments: [core.string(name), encoded, ["pristine": pristine]])
    } }
    public func initialize(defaults: [(String, Materialized)], persisted: [OpenUIString: Value]) { core.sync {
        // Preflight the entire input before materializing or encoding it, even
        // if an existing non-pristine value will later ignore a default.
        guard defaults.count < NativeValueCost.maximumNodes, persisted.count < NativeValueCost.maximumNodes else {
            rejectedMutation = true; return
        }
        var defaultInput = NativeValueCost.container
        var defaultEntries: [(OpenUIString, Materialized, NativeValueCost)] = []
        for (name, value) in defaults {
            guard OpenUIRuntimeBudget.acceptsSource(name) else { rejectedMutation = true; return }
            let key = OpenUIString(name), measured = defaultCost(value)
            defaultInput.append(measured, keyUnits: key.count)
            guard !defaultInput.exceeds else { rejectedMutation = true; return }
            defaultEntries.append((key, value, measured))
        }
        // Defaults and persisted data are separate bridge inputs. Charging
        // them as one graph would reject a valid snapshot of a large default
        // even though persisted wins and the final state contains it once.
        var persistedInput = NativeValueCost.container
        var persistedEntries: [(OpenUIString, Value, NativeValueCost)] = []
        for (name, value) in persisted {
            let measured = cost(value)
            persistedInput.append(measured, keyUnits: name.count)
            guard !persistedInput.exceeds else { rejectedMutation = true; return }
            persistedEntries.append((name, value, measured))
        }
        var candidate = ledger
        for (name, _, measured) in persistedEntries { candidate.replace(name, cost: measured, pristine: false) }
        for (name, _, measured) in defaultEntries {
            if candidate.fields[name] == nil || candidate.fields[name]?.pristine == true {
                candidate.replace(name, cost: measured, pristine: true)
            }
        }
        guard !candidate.exceeds else { rejectedMutation = true; return }
        let encodedDefaults = core.object(defaultEntries.map { ($0.0, core.encode(protocolMaterializedValue($0.1))) })
        let encodedPersisted = core.object(persistedEntries.map { ($0.0, core.encode($0.1)) })
        ledger = candidate
        rejectedMutation = false
        _ = store.invokeMethod("initialize", withArguments: [encodedDefaults, encodedPersisted])
    } }
    public func getSnapshot() -> [OpenUIString: Value] { core.sync {
        Dictionary(core.entries(store.invokeMethod("getSnapshot", withArguments: [])).map { ($0.0, core.decode($0.1)) }, uniquingKeysWith: { _, new in new })
    } }
    public func subscribe(_ listener: @escaping @Sendable () -> Void) -> () -> Void { core.sync {
        let callback: @convention(block) () -> Void = { listener() }
        let unsubscribe = store.invokeMethod("subscribe", withArguments: [callback])!
        let runtime = core
        return { runtime.sync { _ = unsubscribe.call(withArguments: []) } }
    } }
    public func dispose() { core.sync {
        ledger = Ledger(); costs.removeAll(); rejectedMutation = false
        _ = store.invokeMethod("dispose", withArguments: [])
    } }
}
public func createStore() -> Store { CoreStore() }

extension Store {
    /// The SDK Store atomically rejected its most recent set/initialize because
    /// the input or resulting state exceeded the native graph budget. The old
    /// values remain readable; a subsequent accepted write/initialize or dispose
    /// clears this flag. OpenUIState reports failure through its existing error
    /// channel. Custom Store implementations retain their own policy.
    var nativeLimitExceeded: Bool { (self as? CoreStore)?.nativeLimitExceeded ?? false }
}
