/// Narrows live-snapshot matching without deciding which snapshot is safe to
/// use. Property and readiness checks remain at the shared resolution boundary.
/// Ordinary evaluator outputs may recreate every JS/native identity, so this
/// index owns one current graph rather than a persistent container DAG cache.
struct NativeLiveElementIndex {
  fileprivate enum Scalar: Hashable, Sendable {
    case string(OpenUIString), number(UInt64), boolean(Bool), null, undefined

    init?(_ value: Value) {
      switch value {
      case .string(let value): self = .string(value)
      case .number(let value):
        // Final matching uses structural Value equality: all NaNs match and
        // either signed zero belongs to the same candidate bucket.
        self = .number(value.isNaN ? Double.nan.bitPattern : (value == 0 ? 0 : value.bitPattern))
      case .boolean(let value): self = .boolean(value)
      case .null: self = .null
      case .undefined: self = .undefined
      default: return nil
      }
    }
  }
  fileprivate struct ScalarProperty: Hashable, Sendable {
    // Property-name matching uses Swift String equality. Canonically equivalent
    // spellings must share the same readiness-ambiguity bucket.
    let name: String
    let value: Scalar
  }
  fileprivate struct Key: Hashable, Sendable {
    let typeName: String
    let statementID: String?
    let scalarProperties: [ScalarProperty]?

    init(_ element: EvaluatedElement) {
      typeName = element.typeName
      statementID = element.statementId
      guard statementID == nil else { scalarProperties = nil; return }
      var properties: [ScalarProperty] = []
      for (name, value) in element.props {
        guard let scalar = Scalar(value) else { scalarProperties = nil; return }
        properties.append(ScalarProperty(name: name, value: scalar))
      }
      scalarProperties = properties
    }
  }

  /// Presentation changes contain keys only, so accumulating updates cannot retain
  /// retired element graphs. Counts describe index work, never frame timing.
  struct Update: Sendable {
    fileprivate var presentationKeys: Set<Key> = []
    fileprivate(set) var indexedContainers = 0
    fileprivate(set) var comparedCandidates = 0

    init() {}

    func affectsPresentation(for snapshot: EvaluatedElement) -> Bool {
      presentationKeys.contains(Key(snapshot))
    }

    mutating func formUnion(_ other: Self) {
      presentationKeys.formUnion(other.presentationKeys)
      indexedContainers += other.indexedContainers
      comparedCandidates += other.comparedCandidates
    }
  }

  private var root: EvaluatedElement?
  private var buckets: [Key: [EvaluatedElement]] = [:]
  private var members: Set<ObjectIdentifier> = []

  @discardableResult
  mutating func replaceRoot(_ element: EvaluatedElement?) -> Update {
    guard root !== element else { return Update() }
    var update = Update()
    var nextBuckets: [Key: [EvaluatedElement]] = [:]
    var nextMembers: Set<ObjectIdentifier> = []
    // A first deep occurrence must not hide descendants reachable through a
    // later shallower alias. This map lasts for this traversal only.
    var shallowestVisit: [ObjectIdentifier: Int] = [:]
    func accept(_ object: AnyObject, at depth: Int) -> Bool {
      let identity = ObjectIdentifier(object)
      if let previous = shallowestVisit[identity], previous <= depth { return false }
      shallowestVisit[identity] = depth
      update.indexedContainers += 1
      return true
    }
    func visit(_ value: Value, depth: Int) {
      guard depth < NativeValueCost.maximumDepth else { return }
      switch value {
      case .element(let current):
        guard accept(current, at: depth) else { return }
        if nextMembers.insert(ObjectIdentifier(current)).inserted {
          nextBuckets[Key(current), default: []].append(current)
        }
        current.props.forEach { visit($0.1, depth: depth + 1) }
      case .array(let values):
        guard accept(values, at: depth) else { return }
        values.forEach { visit($0, depth: depth + 1) }
      case .object(let values):
        guard accept(values, at: depth) else { return }
        values.forEach { visit($0.value, depth: depth + 1) }
      default: break
      }
    }
    if let element { visit(.element(element), depth: 0) }

    // Membership always follows actual identities. Only a unique scalar leaf
    // can preserve its presentation when its immutable wrapper is recreated.
    // Reference props and ambiguous buckets retain the conservative lookup:
    // losing exact membership can change an old snapshot's resolution there.
    for (key, current) in nextBuckets {
      guard let previous = buckets[key], previous.count == current.count else {
        update.presentationKeys.insert(key)
        continue
      }
      for (left, right) in zip(previous, current) {
        update.comparedCandidates += 1
        if left !== right {
          if current.count != 1 || !left.props.allSatisfy({ Scalar($0.1) != nil })
              || !nativePresentationInputsEqual(left, right) {
            update.presentationKeys.insert(key)
          }
          break
        }
      }
    }
    for key in buckets.keys where nextBuckets[key] == nil {
      update.presentationKeys.insert(key)
    }
    root = element
    buckets = nextBuckets
    members = nextMembers
    return update
  }

  /// Exact membership is separate from semantic matching of an old snapshot.
  func contains(_ element: EvaluatedElement) -> Bool {
    members.contains(ObjectIdentifier(element))
  }

  func candidates(for element: EvaluatedElement) -> [EvaluatedElement] {
    buckets[Key(element)] ?? []
  }
}
