import Dispatch
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// One process-wide listener for the two completed-resource budgets. It does
/// not retain documents or turn a memory warning into a document reset.
@MainActor enum NativeResourceCachePressure {
  #if canImport(UIKit)
  private static var observation: NSObjectProtocol?
  #elseif os(macOS)
  private static var source: DispatchSourceMemoryPressure?
  #endif

  static func startIfNeeded() {
    #if canImport(UIKit)
    guard observation == nil else { return }
    observation = NotificationCenter.default.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification,
      object: nil,
      queue: nil
    ) { _ in
      Task { @MainActor in NativeResourceCacheBudgets.trimCompleted() }
    }
    #elseif os(macOS)
    guard source == nil else { return }
    let pressure = DispatchSource.makeMemoryPressureSource(
      eventMask: [.warning, .critical], queue: .main
    )
    pressure.setEventHandler {
      Task { @MainActor in NativeResourceCacheBudgets.trimCompleted() }
    }
    source = pressure
    pressure.resume()
    #endif
  }
}
