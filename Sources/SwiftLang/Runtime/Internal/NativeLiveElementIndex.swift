
/// Narrows the session's live-snapshot search without deciding which snapshot
/// is safe to use. Property and readiness checks remain in OpenUIState.
struct NativeLiveElementIndex {
  private enum Scalar: Hashable {
    case string(OpenUIString), number(UInt64), boolean(Bool), null, undefined

    init?(_ value: Value) {
      switch value {
      case .string(let value): self = .string(value)
      case .number(let value):
        // Candidate matching below follows structural Value equality: all NaNs
        // match, and either signed zero belongs to the same candidate bucket.
        self = .number(value.isNaN ? Double.nan.bitPattern : (value == 0 ? 0 : value.bitPattern))
      case .boolean(let value): self = .boolean(value)
      case .null: self = .null
      case .undefined: self = .undefined
      default: return nil
      }
    }
  }
  private struct ScalarProperty: Hashable {
    // liveElement's final property-name check uses Swift String equality.
    // Canonically equivalent spellings must share the same ambiguity bucket.
    let name: String
    let value: Scalar
  }
  private struct Key: Hashable {
    let typeName: String
    let statementID: String?
    let scalarProperties: [ScalarProperty]?

    init(_ element: EvaluatedElement) {
      typeName = element.typeName
      statementID = element.statementId
      // Named declarations already have small buckets. Only inline nodes need
      // scalar narrowing; retain the existing declaration candidate grouping.
      guard statementID == nil else { scalarProperties = nil; return }
      var properties: [ScalarProperty] = []
      for (name, value) in element.props {
        guard let scalar = Scalar(value) else { scalarProperties = nil; return }
        properties.append(ScalarProperty(name: name, value: scalar))
      }
      scalarProperties = properties
    }
  }

  private var buckets: [Key: [EvaluatedElement]] = [:]
  private var members: Set<ObjectIdentifier> = []

  mutating func insert(_ element: EvaluatedElement) {
    members.insert(ObjectIdentifier(element))
    buckets[Key(element), default: []].append(element)
  }

  /// A node already in this tree has its current metadata. Only older native
  /// snapshots need the semantic candidate search and ambiguity check.
  func contains(_ element: EvaluatedElement) -> Bool {
    members.contains(ObjectIdentifier(element))
  }

  func candidates(for element: EvaluatedElement) -> [EvaluatedElement] {
    buckets[Key(element)] ?? []
  }

  mutating func removeAll(keepingCapacity: Bool = false) {
    buckets.removeAll(keepingCapacity: keepingCapacity)
    members.removeAll(keepingCapacity: keepingCapacity)
  }
}
