import Foundation
import XCTest
@testable import SwiftLang

final class StoreAggregateBudgetTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
        func increment() { lock.lock(); count += 1; lock.unlock() }
    }
    private func array(_ count: Int) -> Value { .array(Array(repeating: .number(1), count: count)) }

    func testSeparateWritesChargeEveryRetainedOccurrenceAndRecoverByReplacing() {
        let store = createStore(), large = array(60_000)
        let notifications = Counter()
        let unsubscribe = store.subscribe { notifications.increment() }
        defer { unsubscribe(); store.dispose() }
        store.set("$first", value: large, pristine: false)
        XCTAssertFalse(store.nativeLimitExceeded)
        store.set("$second", value: large, pristine: false)
        XCTAssertTrue(store.nativeLimitExceeded)
        XCTAssertEqual(notifications.value, 1)
        XCTAssertNil(store.get("$second"))
        XCTAssertEqual(store.get("$first"), large)
        XCTAssertFalse(nativeStateExceedsLimits(store.getSnapshot()))

        store.set("$first", value: array(30_000), pristine: false)
        XCTAssertFalse(store.nativeLimitExceeded, "An accepted write clears the last rejection")
        store.set("$second", value: large, pristine: false)
        XCTAssertFalse(store.nativeLimitExceeded, "Replacing a field returns its previous allowance")
        XCTAssertEqual(notifications.value, 3)
        XCTAssertFalse(nativeStateExceedsLimits(store.getSnapshot()))
    }

    func testLargeDefaultSnapshotRoundTripCountsOnlyTheFinalWinningField() {
        let large = array(60_000)
        let source = createStore()
        source.initialize(defaults: [("$data", .value(large))], persisted: [:])
        XCTAssertFalse(source.nativeLimitExceeded)
        let snapshot = source.getSnapshot()
        let restored = createStore()
        defer { source.dispose(); restored.dispose() }
        restored.initialize(defaults: [("$data", .value(large))], persisted: snapshot)
        XCTAssertFalse(restored.nativeLimitExceeded,
            "Defaults and persisted are two bounded inputs; persisted wins instead of storing two copies")
        XCTAssertEqual(restored.getSnapshot(), snapshot)
        restored.initialize(defaults: [("$data", .value(.number(4)))], persisted: [:])
        XCTAssertEqual(restored.get("$data"), large, "Restoration made the field non-pristine")
    }

    func testInitializeRejectsAnOversizedCandidateAtomically() {
        let store = createStore()
        defer { store.dispose() }
        store.initialize(defaults: [("$first", .value(.number(7)))], persisted: [:])
        let notifications = Counter()
        let unsubscribe = store.subscribe { notifications.increment() }
        defer { unsubscribe() }
        store.initialize(defaults: [("$second", .value(array(50_000)))],
                         persisted: ["$first": array(60_000)])
        XCTAssertTrue(store.nativeLimitExceeded)
        XCTAssertEqual(store.getSnapshot(), ["$first": .number(7)])
        XCTAssertEqual(notifications.value, 0, "Neither input may partially initialize the store")
        store.initialize(defaults: [("$first", .value(.number(9)))], persisted: [:])
        XCTAssertFalse(store.nativeLimitExceeded)
        XCTAssertEqual(store.get("$first"), .number(9), "A rejected candidate did not change pristine status")
    }

    func testInitializeChecksFinalCandidateWithoutOrderDependentIntermediateRejection() {
        let store = createStore(), large = array(60_000), small = array(30_000)
        defer { store.dispose() }
        store.initialize(defaults: [("$first", .value(large))], persisted: [:])
        store.initialize(defaults: [("$second", .value(large)), ("$first", .value(small))], persisted: [:])
        XCTAssertFalse(store.nativeLimitExceeded)
        XCTAssertEqual(store.get("$first"), small)
        XCTAssertEqual(store.get("$second"), large)
        XCTAssertFalse(nativeStateExceedsLimits(store.getSnapshot()))
    }

    func testInitialUndefinedNoOpDoesNotCreateAPhantomNonPristineLedgerField() {
        let store = createStore(), large = array(60_000)
        defer { store.dispose() }
        store.set("$missing", value: .undefined, pristine: false)
        XCTAssertNil(store.get("$missing"), "Preserve core's absent/undefined SameValue behavior")
        store.set("$kept", value: large, pristine: false)
        store.initialize(defaults: [("$missing", .value(large))], persisted: [:])
        XCTAssertTrue(store.nativeLimitExceeded,
            "The absent key still needs its full default; treating it as non-pristine would undercount")
        XCTAssertNil(store.get("$missing"))
        XCTAssertEqual(store.get("$kept"), large)
    }

    func testSameValueWriteUpdatesPristineBeforeReturningAndIgnoredDefaultsStayIgnored() {
        let store = createStore()
        defer { store.dispose() }
        store.initialize(defaults: [("$x", .value(.number(1)))], persisted: [:])
        store.set("$x", value: .number(1), pristine: false)
        store.initialize(defaults: [("$x", .value(.number(2)))], persisted: [:])
        XCTAssertEqual(store.get("$x"), .number(1))
        store.set("$x", value: .number(1), pristine: true)
        store.initialize(defaults: [("$x", .value(.number(3)))], persisted: [:])
        XCTAssertEqual(store.get("$x"), .number(3))
        XCTAssertFalse(store.nativeLimitExceeded)
    }

    func testRawDefaultsAndContainerDepthRejectBeforeEncoding() {
        let store = createStore()
        defer { store.dispose() }
        store.set("$kept", value: .number(8), pristine: false)
        var raw = Materialized.null
        for _ in 0..<300 { raw = .array([raw]) }
        store.initialize(defaults: [("$raw", raw)], persisted: [:])
        XCTAssertTrue(store.nativeLimitExceeded)
        XCTAssertEqual(store.getSnapshot(), ["$kept": .number(8)])
        var deepest = Value.number(1)
        for _ in 0..<256 { deepest = .array([deepest]) }
        XCTAssertFalse(nativeValueExceedsLimits(deepest))
        store.set("$deep", value: deepest, pristine: false)
        XCTAssertTrue(store.nativeLimitExceeded, "The enclosing state object also consumes one depth level")
        XCTAssertNil(store.get("$deep"))
        store.dispose()
        XCTAssertFalse(store.nativeLimitExceeded)
        XCTAssertTrue(store.getSnapshot().isEmpty)
    }

    func testReentrantSubscriberSeesTheAcceptedCostBeforeItsOwnWrite() {
        let store = createStore(), large = array(60_000)
        let unsubscribe = store.subscribe {
            if store.get("$first") != nil, store.get("$second") == nil {
                store.set("$second", value: large, pristine: false)
            }
        }
        defer { unsubscribe(); store.dispose() }
        store.set("$first", value: large, pristine: false)
        XCTAssertTrue(store.nativeLimitExceeded)
        XCTAssertEqual(store.get("$first"), large)
        XCTAssertNil(store.get("$second"))
        XCTAssertFalse(nativeStateExceedsLimits(store.getSnapshot()))
    }
}
