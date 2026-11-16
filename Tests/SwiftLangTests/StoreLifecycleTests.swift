import Foundation
import XCTest
@testable import SwiftLang

final class StoreLifecycleTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
        func increment() { lock.lock(); count += 1; lock.unlock() }
    }

    func testCoreStoreNotificationsUnsubscribeAndDispose() {
        let store: Store = createStore()
        let notifications = Counter()
        let unsubscribe = store.subscribe { notifications.increment() }
        store.set("$value", value: .number(1), pristine: false)
        XCTAssertEqual(notifications.value, 1)
        store.set("$value", value: .number(1), pristine: false)
        XCTAssertEqual(notifications.value, 1, "Core SameValue suppresses unchanged writes")
        XCTAssertEqual(store.getSnapshot()["$value"], .number(1))

        unsubscribe()
        unsubscribe()
        store.set("$value", value: .number(2), pristine: false)
        XCTAssertEqual(notifications.value, 1)

        _ = store.subscribe { notifications.increment() }
        store.dispose()
        XCTAssertTrue(store.getSnapshot().isEmpty)
        store.set("$value", value: .number(3), pristine: false)
        XCTAssertEqual(notifications.value, 1, "Disposal removes the core's listeners")
    }

    func testKeyedReadsDistinguishMissingUndefinedAndPrototypeNames() throws {
        let store = createStore()
        let object = Value.object([.init(key: "value", value: .number(3))])
        XCTAssertNil(store.get("$missing"))
        XCTAssertNil(store.get("toString"))
        // A prior defined value creates the key; the upstream store ignores an
        // initial undefined write because it equals the absent Map value.
        store.set("$undefined", value: .number(0), pristine: false)
        store.set("$undefined", value: .undefined, pristine: false)
        store.set("$null", value: .null, pristine: false)
        store.set("__proto__", value: object, pristine: false)
        store.set("toString", value: .string("own"), pristine: false)
        XCTAssertEqual(store.get("$undefined"), .undefined)
        XCTAssertEqual(store.get("$null"), .null)
        XCTAssertTrue(try XCTUnwrap(store.get("__proto__")).isSameValue(as: object))
        XCTAssertEqual(store.get("toString"), .string("own"))
        store.dispose()
        XCTAssertNil(store.get("__proto__"))
        XCTAssertNil(store.get("toString"))
    }
}
