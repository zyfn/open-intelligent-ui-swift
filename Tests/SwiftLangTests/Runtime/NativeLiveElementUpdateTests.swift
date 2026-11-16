import Combine
import XCTest
@testable import SwiftLang

final class NativeLiveElementUpdateTests: XCTestCase {
  func testChangingTailPreservesCurrentMembershipAndUnchangedCandidateKeys() {
    let stableChildren = (0..<600).map { text("stable-\($0)", "Same") }
    let stable = container(stableChildren, id: "stable")
    let before = text("tail", "Before")
    let after = text("tail", "After")
    var index = NativeLiveElementIndex()
    index.replaceRoot(container([stable, before], id: "root"))
    let update = index.replaceRoot(container([stable, after], id: "root"))

    XCTAssertGreaterThan(update.indexedContainers, 600,
      "A new root still uses one complete index walk; this is not an incremental-evaluation claim")
    XCTAssertLessThanOrEqual(update.comparedCandidates, stableChildren.count + 3,
      "Changed-key comparison must be shallow and bounded by the current candidates")
    XCTAssertTrue(index.contains(after))
    XCTAssertFalse(index.contains(before))
    for child in stableChildren {
      XCTAssertTrue(index.contains(child))
      XCTAssertFalse(update.affectsLookup(for: child))
    }
    XCTAssertTrue(update.affectsLookup(for: before))
    XCTAssertTrue(update.affectsLookup(for: after))
  }

  func testIdenticalRootDoesNoIndexWork() {
    let root = container([text("child", "Same")], id: "root")
    var index = NativeLiveElementIndex()
    index.replaceRoot(root)
    let update = index.replaceRoot(root)
    XCTAssertEqual(update.indexedContainers, 0)
    XCTAssertEqual(update.comparedCandidates, 0)
    XCTAssertFalse(update.affectsLookup(for: root))
  }

  func testSharedSubtreeSurvivesRemovingOnlyOneParent() {
    let leaf = text("leaf", "Shared")
    let shared = container([leaf], id: "shared")
    let left = container([shared], id: "left")
    let right = container([shared], id: "right")
    var index = NativeLiveElementIndex()
    index.replaceRoot(container([left, right], id: "root"))
    let update = index.replaceRoot(container([right], id: "root"))

    XCTAssertFalse(index.contains(left))
    XCTAssertTrue(index.contains(right))
    XCTAssertTrue(index.contains(shared))
    XCTAssertTrue(index.contains(leaf))
    XCTAssertFalse(update.affectsLookup(for: leaf))
    assertIdentities(index.candidates(for: leaf), [leaf])
    index.replaceRoot(nil)
    XCTAssertFalse(index.contains(leaf))
    XCTAssertTrue(index.candidates(for: leaf).isEmpty)
  }

  func testAliasesAtDifferentDepthsStillHaveOneElementMembership() {
    let shared = text("shared", "Same")
    let nested = container([shared, shared], id: "nested")
    var index = NativeLiveElementIndex()
    index.replaceRoot(container([shared, nested], id: "root"))
    assertIdentities(index.candidates(for: shared), [shared])

    index.replaceRoot(container([nested], id: "root"))
    XCTAssertTrue(index.contains(shared))
    assertIdentities(index.candidates(for: shared), [shared])
    index.replaceRoot(container([], id: "root"))
    XCTAssertFalse(index.contains(shared))
  }

  func testReadinessReplacementRetiresOnlyTheOldSnapshot() {
    let pending = text("button", "Same", complete: false)
    let ready = text("button", "Same", complete: true)
    var index = NativeLiveElementIndex()
    index.replaceRoot(pending)
    let update = index.replaceRoot(ready)

    XCTAssertFalse(index.contains(pending))
    XCTAssertTrue(index.contains(ready))
    assertIdentities(index.candidates(for: pending), [ready])
    XCTAssertTrue(update.affectsLookup(for: pending))
    XCTAssertTrue(update.affectsPresentation(for: pending))
    XCTAssertFalse(pending.isSourceComplete, "Indexing must not mutate an older readiness snapshot")
  }

  func testReorderKeepsCurrentDFSOrderAndInvalidatesAmbiguousLookups() {
    let pending = text("shared", "Same", complete: false)
    let ready = text("shared", "Same", complete: true)
    let stale = text("shared", "Same", complete: false)
    var index = NativeLiveElementIndex()
    index.replaceRoot(container([pending, ready], id: "root"))
    assertIdentities(index.candidates(for: stale), [pending, ready])

    let update = index.replaceRoot(container([ready, pending], id: "root"))
    assertIdentities(index.candidates(for: stale), [ready, pending])
    XCTAssertTrue(update.affectsLookup(for: stale),
      "Surviving identities alone do not prove the same first-match order")
    XCTAssertTrue(index.contains(pending))
    XCTAssertTrue(index.contains(ready))
  }

  func testEqualButDistinctSnapshotsRemainSeparateMembers() {
    let first = text("shared", "Same")
    let second = text("shared", "Same")
    XCTAssertEqual(first, second)
    var index = NativeLiveElementIndex()
    index.replaceRoot(container([first, second], id: "root"))
    assertIdentities(index.candidates(for: first), [first, second])
    index.replaceRoot(container([second], id: "root"))
    XCTAssertFalse(index.contains(first))
    XCTAssertTrue(index.contains(second))
    assertIdentities(index.candidates(for: first), [second])
  }

  func testRecreatedEqualCandidatesProduceChangesWithoutMergingTheirIdentities() {
    let previous = (0..<200).map { text("row-\($0)", "Same") }
    let current = (0..<200).map { text("row-\($0)", "Same") }
    var index = NativeLiveElementIndex()
    index.replaceRoot(container(previous, id: "root"))
    let update = index.replaceRoot(container(current, id: "root"))

    XCTAssertLessThanOrEqual(update.comparedCandidates, current.count + 1)
    for (old, new) in zip(previous, current) {
      XCTAssertEqual(old, new)
      XCTAssertFalse(index.contains(old))
      XCTAssertTrue(index.contains(new))
      XCTAssertTrue(update.affectsLookup(for: old))
      XCTAssertFalse(update.affectsPresentation(for: old),
        "A unique scalar leaf can keep its presentation while membership follows the new object")
      assertIdentities(index.candidates(for: old), [new])
    }
  }

  func testRecreatedAmbiguousCandidatesStillRequirePresentationResolution() {
    let pending = text("shared", "Same", complete: false)
    let ready = text("shared", "Same", complete: true)
    var index = NativeLiveElementIndex()
    index.replaceRoot(container([pending, ready], id: "root"))
    let update = index.replaceRoot(container([
      text("shared", "Same", complete: false), text("shared", "Same", complete: true)
    ], id: "root"))

    XCTAssertTrue(update.affectsPresentation(for: ready),
      "An exact member becomes an ambiguous old snapshot when both identities are replaced")
    XCTAssertTrue(nativeResolveLiveElement(ready, in: index) === ready)
  }

  func testReferencePropsKeepTheConservativePresentationDelta() {
    let data = Value.array([.number(1)])
    let previous = EvaluatedElement(typeName: "Data", props: [("data", data)], statementId: "data")
    let current = EvaluatedElement(typeName: "Data", props: previous.props, statementId: "data")
    var index = NativeLiveElementIndex()
    index.replaceRoot(previous)
    let update = index.replaceRoot(current)
    XCTAssertTrue(update.affectsLookup(for: previous))
    XCTAssertTrue(update.affectsPresentation(for: previous),
      "Reference values retain the existing structural/depth and readiness resolution")
  }

  @MainActor func testRealStreamingTextDoesNotRefreshStableScalarPresentations() throws {
    let schema = LibrarySchema(components: [
      "Stack": [ParamDef(name: "children", required: true)],
      "TextContent": [ParamDef(name: "text", required: true)]
    ], callDefs: builtinCallDefs, rootComponent: "Stack")
    let state = OpenUIState(schema: schema)
    defer { state.reset() }
    let ids = (0..<40).map { "row\($0)" }
    let declarations = ids.map { "\($0)=TextContent(\"Stable \($0)\")" }.joined(separator: "\n")
    state.push("root=Stack([\((ids + ["tail"]).joined(separator: ","))])\n\(declarations)\ntail=TextContent(\"A")
    let stable = Array(PropValue.children(try XCTUnwrap(state.root)).prefix(ids.count))
    XCTAssertEqual(stable.count, ids.count)
    let subscriptions = stable.map { node in
      let subscription = NativeComponentSubscription()
      _ = subscription.begin(element: node, state: state)
      return subscription
    }
    var notifications = 0
    let observers = subscriptions.map { $0.objectWillChange.sink { notifications += 1 } }
    defer { observers.forEach { $0.cancel() } }
    var index = NativeLiveElementIndex()
    index.replaceRoot(state.root)

    for chunk in [" growing", " streamed", " paragraph", " with Unicode 苏州"] {
      state.push(chunk)
      let update = index.replaceRoot(try XCTUnwrap(state.root))
      for node in stable {
        XCTAssertFalse(update.affectsPresentation(for: node),
          "Check real evaluator output, without manufacturing shared native leaf identities")
      }
      XCTAssertEqual(notifications, 0, "Stable scalar subscriptions must stay quiet during the real text stream")
    }
  }

  func testChangesAccumulateAcrossSeveralUpdatesBeforeNotification() {
    let first = text("first", "Before")
    let second = text("second", "Before")
    let stable = text("stable", "Same")
    let nextFirst = text("first", "After")
    let nextSecond = text("second", "After")
    var index = NativeLiveElementIndex()
    index.replaceRoot(container([first, second, stable], id: "root"))
    var accumulated = NativeLiveElementIndex.Update()
    accumulated.formUnion(index.replaceRoot(container([nextFirst, second, stable], id: "root")))
    accumulated.formUnion(index.replaceRoot(container([nextFirst, nextSecond, stable], id: "root")))

    XCTAssertTrue(accumulated.affectsLookup(for: first))
    XCTAssertTrue(accumulated.affectsLookup(for: second))
    XCTAssertFalse(accumulated.affectsLookup(for: stable))
    XCTAssertTrue(accumulated.affectsPresentation(for: first))
    XCTAssertTrue(accumulated.affectsPresentation(for: second))
    XCTAssertFalse(accumulated.affectsPresentation(for: stable))
    XCTAssertFalse(index.contains(first))
    XCTAssertFalse(index.contains(second))
    XCTAssertTrue(index.contains(nextFirst))
    XCTAssertTrue(index.contains(nextSecond))
  }

  func testRetainedUpdateDoesNotRetainTheRemovedValueGraph() {
    var index = NativeLiveElementIndex()
    weak var retired: EvaluatedElement?
    do {
      let value = container([text("child", "Old")], id: "old")
      retired = value
      index.replaceRoot(value)
    }
    XCTAssertNotNil(retired)
    let update = index.replaceRoot(nil)
    XCTAssertNil(retired)
    XCTAssertTrue(update.affectsLookup(for: container([], id: "old")))
  }

  func testMovingAStableSubtreeAcrossDepthLimitRecomputesItsReachability() {
    let leaf = text("leaf", "Deep")
    let subtree = wrapping(leaf, count: 1)
    var index = NativeLiveElementIndex()
    index.replaceRoot(subtree)
    XCTAssertTrue(index.contains(leaf))

    let deeper = index.replaceRoot(wrapping(subtree, count: 255))
    XCTAssertTrue(index.contains(subtree), "Depth 255 remains inside the index boundary")
    XCTAssertFalse(index.contains(leaf), "Depth 256 must not reuse shallower cached membership")
    XCTAssertTrue(deeper.affectsLookup(for: leaf))

    let shallower = index.replaceRoot(subtree)
    XCTAssertTrue(index.contains(leaf))
    XCTAssertTrue(shallower.affectsLookup(for: leaf))
  }

  func testDeepFirstAliasDoesNotHideDescendantsOfAShallowerOccurrence() {
    let leaf = text("leaf", "Shared")
    let subtree = wrapping(leaf, count: 1)
    let root = EvaluatedElement(typeName: "Root", props: [
      ("deep", .element(wrapping(subtree, count: 254))),
      ("shallow", .element(subtree))
    ])
    var index = NativeLiveElementIndex()
    index.replaceRoot(root)
    XCTAssertTrue(index.contains(leaf),
      "The first, depth-limited occurrence must not suppress a later valid path")
    assertIdentities(index.candidates(for: leaf), [leaf])
  }

  private func text(_ id: String, _ value: String, complete: Bool = true) -> EvaluatedElement {
    EvaluatedElement(typeName: "TextContent", props: [("text", .string(OpenUIString(value)))],
      statementId: id, isSourceComplete: complete)
  }

  private func container(_ children: [EvaluatedElement], id: String) -> EvaluatedElement {
    EvaluatedElement(typeName: "Stack", props: [("children", .array(children.map { .element($0) }))],
      statementId: id)
  }

  private func wrapping(_ element: EvaluatedElement, count: Int) -> EvaluatedElement {
    var result = element
    for _ in 0..<count {
      result = EvaluatedElement(typeName: "Wrapper", props: [("child", .element(result))])
    }
    return result
  }

  private func assertIdentities(_ actual: [EvaluatedElement], _ expected: [EvaluatedElement],
                                file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(actual.map(ObjectIdentifier.init), expected.map(ObjectIdentifier.init), file: file, line: line)
  }
}
