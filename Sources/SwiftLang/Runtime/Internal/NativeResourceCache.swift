import Foundation

/// These limits cover completed SDK cache entries, not mounted images, active
/// requests, language state, or the process footprint. Values remain owned by
/// each document; the shared budgets keep only weak cache registrations.
@MainActor enum NativeResourceCacheBudgets {
  // Two full per-document image caches and four full byte caches can coexist.
  // Count limits also bound the bookkeeping for tiny or empty resources.
  private static let imagePool = NativeResourceCacheBudget(maximumCost: 64 * 1024 * 1024, maximumCount: 128)
  private static let bytePool = NativeResourceCacheBudget(maximumCost: 8 * 1024 * 1024, maximumCount: 128)

  static var decodedImages: NativeResourceCacheBudget {
    NativeResourceCachePressure.startIfNeeded()
    return imagePool
  }
  static var responseBytes: NativeResourceCacheBudget {
    NativeResourceCachePressure.startIfNeeded()
    return bytePool
  }
  /// Drop only rebuildable completed values. Request leases, pending consumers,
  /// document epochs, Store values, and Query execution remain valid.
  static func trimCompleted() {
    imagePool.removeAll()
    bytePool.removeAll()
  }
}

@MainActor fileprivate protocol NativeResourceCacheOwner: AnyObject {
  var retainedCount: Int { get }
  var retainedCost: Int { get }
  var oldestAccess: UInt64? { get }
  func evictOldest()
  func removeAll()
}

@MainActor final class NativeResourceCacheBudget {
  private final class WeakOwner {
    weak var value: (any NativeResourceCacheOwner)?
    init(_ value: any NativeResourceCacheOwner) { self.value = value }
  }
  private let maximumCost: Int
  private let maximumCount: Int
  private var owners: [ObjectIdentifier: WeakOwner] = [:]
  private var access: UInt64 = 0

  init(maximumCost: Int, maximumCount: Int) {
    self.maximumCost = max(0, maximumCost)
    self.maximumCount = max(0, maximumCount)
  }
  var retainedCount: Int { liveOwners().reduce(0) { $0 + $1.retainedCount } }
  var retainedCost: Int { liveOwners().reduce(0) { $0 + $1.retainedCost } }

  fileprivate func nextAccess() -> UInt64 {
    access &+= 1
    return access
  }
  fileprivate func accepts(cost: Int) -> Bool {
    cost >= 0 && cost <= maximumCost && maximumCount > 0
  }
  fileprivate func forget(_ owner: any NativeResourceCacheOwner) {
    owners.removeValue(forKey: ObjectIdentifier(owner))
  }
  fileprivate func inserted(_ owner: any NativeResourceCacheOwner) {
    guard owner.retainedCount > 0 else { return }
    owners[ObjectIdentifier(owner)] = WeakOwner(owner)
    var active = liveOwners()
    var count = active.reduce(0) { $0 + $1.retainedCount }
    var cost = active.reduce(0) { $0 + $1.retainedCost }
    while count > maximumCount || cost > maximumCost {
      guard let oldest = active.min(by: { ($0.oldestAccess ?? .max) < ($1.oldestAccess ?? .max) }) else { break }
      let previousCost = oldest.retainedCost
      oldest.evictOldest()
      count -= 1
      cost -= previousCost - oldest.retainedCost
      if oldest.retainedCount == 0 { active.removeAll { $0 === oldest } }
    }
  }
  private func liveOwners() -> [any NativeResourceCacheOwner] {
    owners = owners.filter { ($0.value.value?.retainedCount ?? 0) > 0 }
    return owners.values.compactMap(\.value)
  }
  func removeAll() {
    let active = liveOwners()
    owners.removeAll()
    for owner in active { owner.removeAll() }
  }
}

/// One value store with local limits and a shared LRU budget. Reads only update
/// an access stamp; insertion scans at most the pool's bounded nonempty owners.
@MainActor final class NativeResourceCache<Key: Hashable, Value>: NativeResourceCacheOwner {
  private struct Entry {
    var value: Value
    let cost: Int
    var access: UInt64
  }
  private var entries: [Key: Entry] = [:]
  private let maximumCost: Int
  private let maximumCount: Int
  private let budget: NativeResourceCacheBudget
  private(set) var retainedCost = 0
  var retainedCount: Int { entries.count }
  var keys: [Key] { Array(entries.keys) }
  fileprivate var oldestAccess: UInt64? { entries.values.map(\.access).min() }

  init(maximumCost: Int, maximumCount: Int, budget: NativeResourceCacheBudget) {
    self.maximumCost = max(0, maximumCost)
    self.maximumCount = max(0, maximumCount)
    self.budget = budget
  }
  subscript(_ key: Key) -> Value? {
    guard var entry = entries[key] else { return nil }
    entry.access = budget.nextAccess()
    entries[key] = entry
    return entry.value
  }
  func accepts(cost: Int) -> Bool {
    cost <= maximumCost && maximumCount > 0 && budget.accepts(cost: cost)
  }
  func insert(_ value: Value, for key: Key, cost: Int) {
    // A failed cache admission must not discard an older usable value.
    guard accepts(cost: cost) else { return }
    if let previous = entries[key] { retainedCost -= previous.cost }
    entries[key] = Entry(value: value, cost: cost, access: budget.nextAccess())
    retainedCost += cost
    while entries.count > maximumCount || retainedCost > maximumCost { evictOldest() }
    budget.inserted(self)
  }
  func update(_ key: Key, _ body: (inout Value) -> Void) {
    guard var entry = entries[key] else { return }
    body(&entry.value)
    entry.access = budget.nextAccess()
    entries[key] = entry
  }
  func removeValue(forKey key: Key) {
    guard let removed = entries.removeValue(forKey: key) else { return }
    retainedCost -= removed.cost
    if entries.isEmpty { budget.forget(self) }
  }
  fileprivate func evictOldest() {
    guard let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key else { return }
    removeValue(forKey: oldest)
  }
  func removeAll() {
    entries.removeAll()
    retainedCost = 0
    budget.forget(self)
  }
}
