import OpenUILang

/// Structural streaming placeholders are registered metadata, never guessed
/// components or data. They do not enter the language store or action values.
package enum OpenUIPresentationProxy {
  package static func element(_ source: NativeSourceReadiness, registry: OpenUIComponentRegistry) -> EvaluatedElement? {
    guard let hint = source.placeholder, registry.supportsPresentationPlaceholder(hint.typeName) else { return nil }
    // Only committed layout scalars are supplied. Required data/actions stay
    // absent, so a proxy cannot fabricate samples, fetch media or be activated.
    let allowed = Set(registry.presentationPlaceholderFields(hint.typeName))
      .union(registry.presentationLayoutFields(hint.typeName))
    let properties = hint.properties.filter { field in
      guard allowed.contains(field.key.displayString) else { return false }
      switch field.value {
      case .string, .boolean, .null: return true
      case .number(let number): return number.isFinite
      default: return false
      }
    }
    let fields = properties.map { ($0.key.displayString, $0.value) }
    let known = Dictionary(properties.keys.map { ($0, NativeSourceReadiness(complete: true, closed: true)) },
      uniquingKeysWith: { _, last in last })
    let readiness = NativeSourceReadiness(complete: false, closed: source.closed,
      children: source.children.merging(known, uniquingKeysWith: { _, committed in committed }),
      queryDependencies: source.queryDependencies, placeholder: hint)
    return EvaluatedElement(typeName: hint.typeName, props: fields, statementId: hint.statementId,
      partial: true, isSourceComplete: false, sourceReadiness: readiness)
  }

  package static func children(_ value: Value, source: NativeSourceReadiness, registry: OpenUIComponentRegistry) -> [OpenUIRenderChild] {
    OpenUIRenderChild.children(of: expandedValue(value, source: source, registry: registry), registry: registry)
  }

  package static func expandedValue(_ value: Value, source: NativeSourceReadiness, registry: OpenUIComponentRegistry) -> Value {
    func expanded(_ value: Value, _ source: NativeSourceReadiness, depth: Int = 0) -> Value {
      guard depth < 256 else { return value }
      if case .array(let values) = value {
        if let slots = source.valueIndices, slots.compactMap({ $0 }) == Array(values.indices) {
          return .array(slots.enumerated().map { position, index in
            if let index { return expanded(values[index], source[index], depth: depth + 1) }
            return source.pendingChildren[position].flatMap { element($0, registry: registry) }.map(Value.element) ?? .null
          })
        }
        guard !source.children.isEmpty else { return value }
        return .array(values.enumerated().map { expanded($0.element, source[$0.offset], depth: depth + 1) })
      }
      if value.isNullish, let proxy = element(source, registry: registry) { return .element(proxy) }
      return value
    }
    return expanded(value, source)
  }
}
