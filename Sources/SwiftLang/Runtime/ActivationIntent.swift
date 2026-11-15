import Foundation
import SwiftUI

/// A reading drag must not also activate a child button/link. This metadata
/// never disables scrolling or continuous bindings, and observes the pager's
/// existing gesture instead of installing a competing zero-distance drag.
package final class NativeActivationIntent {
  private let now: () -> TimeInterval
  private var dragging = false
  private var endedAt = -TimeInterval.infinity
  package init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) { self.now = now }
  package func moved() { dragging = true }
  package func ended() { if dragging { dragging = false; endedAt = now() } }
  package var permitsActivation: Bool { !dragging && now() - endedAt >= 0.25 }
}
private struct NativeActivationIntentKey: EnvironmentKey { static let defaultValue: NativeActivationIntent? = nil }
extension EnvironmentValues {
  package var openUIActivationIntent: NativeActivationIntent? {
    get { self[NativeActivationIntentKey.self] }
    set { self[NativeActivationIntentKey.self] = newValue }
  }
}
