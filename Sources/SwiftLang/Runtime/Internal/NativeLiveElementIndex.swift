
/// Narrows the session's live-snapshot search without deciding which snapshot
/// is safe to use. Property and readiness checks remain in OpenUIState.
struct NativeLiveElementIndex {
  private struct Key: Hashable {
    let typeName: String
    let statementID: String?

    init(_ element: EvaluatedElement) {
      typeName = element.typeName
      statementID = element.statementId
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
