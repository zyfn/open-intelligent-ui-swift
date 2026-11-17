import SwiftLang
import Combine
import MarkdownUI
import XCTest
@testable import SwiftOpenUI

final class StreamingTextPresentationTests: XCTestCase {
  @MainActor private final class ManualScheduler {
    var deliveries: [@MainActor () -> Void] = []
    var cancelled = Set<Int>()

    func schedule(_ delivery: @escaping @MainActor () -> Void) -> NativeStreamingTextBuffer.Cancellation {
      let index = deliveries.count
      deliveries.append(delivery)
      return { [weak self] in self?.cancelled.insert(index) }
    }

    func fire(_ index: Int, evenIfCancelled: Bool = false) {
      guard deliveries.indices.contains(index), evenIfCancelled || !cancelled.contains(index) else { return }
      deliveries[index]()
    }
  }

  @MainActor func testRapidAppendSchedulesOneDeliveryAndKeepsLatestSuffix() {
    let clock = ManualScheduler()
    let buffer = NativeStreamingTextBuffer(schedule: clock.schedule)
    buffer.receive("A", streaming: true)
    for count in 1...50 { buffer.receive("A" + String(repeating: "b", count: count), streaming: true) }
    XCTAssertEqual(buffer.displayed, "A")
    XCTAssertEqual(clock.deliveries.count, 1)
    clock.fire(0)
    XCTAssertEqual(buffer.displayed, "A" + String(repeating: "b", count: 50))
  }

  @MainActor func testDuplicatePendingSnapshotDoesNotExtendItsDeliveryWindow() {
    let clock = ManualScheduler()
    let buffer = NativeStreamingTextBuffer(schedule: clock.schedule)
    buffer.receive("A", streaming: true)
    for _ in 0..<100 { buffer.receive("AB", streaming: true) }
    XCTAssertEqual(clock.deliveries.count, 1)
    XCTAssertTrue(clock.cancelled.isEmpty)
    clock.fire(0)
    XCTAssertEqual(buffer.displayed, "AB")
  }

  @MainActor func testCompletionShowsExactFinalTextAndRejectsLateDelivery() {
    let clock = ManualScheduler()
    let buffer = NativeStreamingTextBuffer(schedule: clock.schedule)
    buffer.receive("initial", streaming: true)
    buffer.receive("initial growing", streaming: true)
    buffer.receive("initial growing final", streaming: false)
    XCTAssertEqual(buffer.displayed, "initial growing final")
    clock.fire(0, evenIfCancelled: true)
    XCTAssertEqual(buffer.displayed, "initial growing final")
  }

  @MainActor func testCorrectionOfPendingSuffixIsImmediate() {
    let clock = ManualScheduler()
    let buffer = NativeStreamingTextBuffer(schedule: clock.schedule)
    buffer.receive("A", streaming: true)
    buffer.receive("AB", streaming: true)
    // Both extend the displayed "A", but AC does not extend the accepted AB.
    XCTAssertEqual(buffer.text(for: "AC", streaming: true), "AC")
    buffer.receive("AC", streaming: true)
    XCTAssertEqual(buffer.displayed, "AC")
    clock.fire(0, evenIfCancelled: true)
    XCTAssertEqual(buffer.displayed, "AC")
  }

  @MainActor func testRevertingToVisiblePrefixCancelsObsoleteSuffix() {
    let clock = ManualScheduler()
    let buffer = NativeStreamingTextBuffer(schedule: clock.schedule)
    buffer.receive("A", streaming: true)
    buffer.receive("AB", streaming: true)
    buffer.receive("A", streaming: true)
    clock.fire(0, evenIfCancelled: true)
    XCTAssertEqual(buffer.displayed, "A")
  }

  @MainActor func testOldDeliveryCannotFlushANewerScheduledGeneration() {
    let clock = ManualScheduler()
    let buffer = NativeStreamingTextBuffer(schedule: clock.schedule)
    buffer.receive("old", streaming: true)
    buffer.receive("old append", streaming: true)
    buffer.receive("new", streaming: true)
    buffer.receive("new append", streaming: true)
    XCTAssertEqual(clock.deliveries.count, 2)
    clock.fire(0, evenIfCancelled: true)
    XCTAssertEqual(buffer.displayed, "new")
    clock.fire(1)
    XCTAssertEqual(buffer.displayed, "new append")
  }

  @MainActor func testCancelAndReappearWithSameInputRestartsPendingDelivery() {
    let clock = ManualScheduler()
    let buffer = NativeStreamingTextBuffer(schedule: clock.schedule)
    buffer.receive("A", streaming: true)
    buffer.receive("AB", streaming: true)
    buffer.cancel()
    clock.fire(0, evenIfCancelled: true)
    XCTAssertEqual(buffer.displayed, "A")
    buffer.receive("AB", streaming: true)
    XCTAssertEqual(clock.deliveries.count, 2)
    clock.fire(1)
    XCTAssertEqual(buffer.displayed, "AB")
  }

  @MainActor func testUTF16DistinctReplacementIsNotSkipped() {
    let buffer = NativeStreamingTextBuffer()
    buffer.receive("\u{00E9}", streaming: true)
    buffer.receive("e\u{0301}", streaming: true)
    XCTAssertEqual(Array((buffer.displayed ?? "").utf16), Array("e\u{0301}".utf16))
  }

  @MainActor func testReadingPresentationDoesNotScheduleOrPublishWork() {
    let clock = ManualScheduler()
    let buffer = NativeStreamingTextBuffer(schedule: clock.schedule)
    buffer.receive("A", streaming: true)
    for _ in 0..<100 {
      XCTAssertEqual(buffer.text(for: "AB", streaming: true), "A")
      XCTAssertEqual(buffer.text(for: "replaced", streaming: true), "replaced")
      XCTAssertEqual(buffer.text(for: "AB", streaming: false), "AB")
    }
    XCTAssertEqual(buffer.displayed, "A")
    XCTAssertTrue(clock.deliveries.isEmpty)
  }

  @MainActor func testSynchronousSchedulerDoesNotRetainAnObsoleteHandle() {
    var deliveries = 0
    let buffer = NativeStreamingTextBuffer(schedule: { deliver in
      deliveries += 1
      deliver()
      return { }
    })
    buffer.receive("A", streaming: true)
    buffer.receive("AB", streaming: true)
    buffer.receive("ABC", streaming: true)
    XCTAssertEqual(deliveries, 2)
    XCTAssertEqual(buffer.displayed, "ABC")
  }

  @MainActor func testPendingDeliveryDoesNotRetainTheBuffer() {
    let clock = ManualScheduler()
    weak var weakBuffer: NativeStreamingTextBuffer?
    do {
      let buffer = NativeStreamingTextBuffer(schedule: clock.schedule)
      weakBuffer = buffer
      buffer.receive("A", streaming: true)
      buffer.receive("AB", streaming: true)
    }
    XCTAssertNil(weakBuffer)
    clock.fire(0)
  }

  @MainActor func testRepeatedFlushDoesNotRepublishAnUnchangedValue() {
    let clock = ManualScheduler()
    let buffer = NativeStreamingTextBuffer(schedule: clock.schedule)
    var values: [String] = []
    let subscription = buffer.$displayed.compactMap { $0 }.sink { values.append($0) }
    defer { subscription.cancel() }
    buffer.receive("A", streaming: true)
    buffer.receive("AB", streaming: true)
    buffer.flush()
    buffer.flush()
    buffer.receive("AB", streaming: false)
    clock.fire(0, evenIfCancelled: true)
    XCTAssertEqual(values, ["A", "AB"])
  }

  @MainActor func testDefaultSchedulerEventuallyDeliversWithoutAssumingAnExactWakeTime() async {
    let buffer = NativeStreamingTextBuffer()
    let delivered = expectation(description: "Latest presentation was actually published")
    let subscription = buffer.$displayed.sink { value in
      if value == "AB" { delivered.fulfill() }
    }
    defer { subscription.cancel(); buffer.cancel() }
    buffer.receive("A", streaming: true)
    buffer.receive("AB", streaming: true)
    await fulfillment(of: [delivered], timeout: 3)
    XCTAssertEqual(buffer.displayed, "AB")
  }
}

extension StreamingTextPresentationTests {
  @MainActor func testPendingFirstMarkdownPreparationReusesFallbackAndPublishesIntermediateProgress() async {
    let worker = ControlledMarkdownPreparation()
    let document = NativeMarkdownDocument(prepare: worker.prepare)
    defer { document.cancel(); worker.cancelRemaining() }
    let initial = markdownRequest("Start")
    XCTAssertEqual(document.content(for: initial).renderPlainText(), "Start")
    document.receive(initial)
    await waitForMarkdownWork(worker, started: 1)

    var latest = initial
    for count in 1...100 {
      latest = markdownRequest("Start " + String(repeating: "x", count: count))
      XCTAssertEqual(document.content(for: latest).renderPlainText(), "Start")
      document.receive(latest)
    }
    XCTAssertEqual(document.fallbackParseCount, 1)
    XCTAssertEqual(document.preparationCount, 1)
    XCTAssertEqual(worker.requests, [initial])

    // The first useful result is visible while a newer prefix is still pending.
    // A producer never needs to complete the language stream to make progress.
    worker.finish(0, markdown: "**Prepared start**")
    await waitForMarkdownWork(worker, started: 2)
    XCTAssertEqual(document.currentSource, initial.source)
    XCTAssertEqual(document.content(for: latest).renderPlainText(), "Prepared start")
    XCTAssertEqual(worker.requests, [initial, latest])

    let intermediate = latest
    latest = markdownRequest(latest.source.displayString + " final")
    document.receive(latest)
    worker.finish(1)
    await waitForMarkdownWork(worker, started: 3)
    XCTAssertEqual(document.currentSource, intermediate.source)
    XCTAssertEqual(document.content(for: latest).renderPlainText(), intermediate.source.displayString)
    worker.finish(2)
    await waitForMarkdownResult(document, source: latest.source)
    XCTAssertEqual(document.content(for: latest).renderPlainText(), latest.source.displayString)
    XCTAssertEqual(document.fallbackParseCount, 1)
  }

  @MainActor func testMarkdownSharedPrefixCorrectionIsImmediateBeforeAndAfterDelivery() async {
    // A -> AB -> AC is not append-only, including when A has already been prepared.
    for prepareInitial in [false, true] {
      let worker = ControlledMarkdownPreparation()
      let document = NativeMarkdownDocument(prepare: worker.prepare)
      defer { document.cancel(); worker.cancelRemaining() }
      let initial = markdownRequest("A"), pending = markdownRequest("AB"), corrected = markdownRequest("AC")
      _ = document.content(for: initial)
      document.receive(initial)
      await waitForMarkdownWork(worker, started: 1)
      if prepareInitial {
        worker.finish(0)
        await waitForMarkdownResult(document, source: initial.source)
      }
      _ = document.content(for: pending)
      document.receive(pending)
      if prepareInitial { await waitForMarkdownWork(worker, started: 2) }
      XCTAssertEqual(document.content(for: corrected).renderPlainText(), "AC",
        "A corrected suffix must be readable before onChange delivers its request")
      let fallbacks = document.fallbackParseCount
      document.receive(corrected)
      await waitForMarkdownWork(worker, started: prepareInitial ? 3 : 2)
      XCTAssertEqual(document.content(for: corrected).renderPlainText(), "AC")
      XCTAssertEqual(document.fallbackParseCount, fallbacks,
        "Delivery must preserve the replacement fallback already produced by the body")

      worker.finish(prepareInitial ? 1 : 0, markdown: "Obsolete input")
      await waitForMarkdownReturns(worker, count: prepareInitial ? 2 : 1)
      XCTAssertNil(document.currentSource)
      XCTAssertEqual(document.content(for: corrected).renderPlainText(), "AC")
      worker.finish(prepareInitial ? 2 : 1)
      await waitForMarkdownResult(document, source: corrected.source)
      XCTAssertEqual(document.content(for: corrected).renderPlainText(), "AC")
    }
  }

  @MainActor func testMarkdownConfigurationChangeRetiresPreparedAndPendingContent() async {
    let initial = markdownRequest("Body"), pending = markdownRequest("Body extended")
    let changed = [
      markdownRequest("Body extended", mode: .inline),
      markdownRequest("Body extended", fontSize: 24),
      markdownRequest("Body extended", color: "#ffffff"),
    ]
    for replacement in changed {
      let worker = ControlledMarkdownPreparation()
      let document = NativeMarkdownDocument(prepare: worker.prepare)
      defer { document.cancel(); worker.cancelRemaining() }
      _ = document.content(for: initial)
      document.receive(initial)
      await waitForMarkdownWork(worker, started: 1)
      worker.finish(0, markdown: "Old math or citation presentation")
      await waitForMarkdownResult(document, source: initial.source)
      document.receive(pending)
      await waitForMarkdownWork(worker, started: 2)

      XCTAssertEqual(document.content(for: replacement).renderPlainText(), "Body extended")
      let fallbacks = document.fallbackParseCount
      document.receive(replacement)
      await waitForMarkdownWork(worker, started: 3)
      worker.finish(1, markdown: "Obsolete configuration")
      await waitForMarkdownReturns(worker, count: 2)
      XCTAssertNil(document.currentSource)
      XCTAssertEqual(document.content(for: replacement).renderPlainText(), "Body extended")
      XCTAssertEqual(document.fallbackParseCount, fallbacks)
      worker.finish(2, markdown: "Current configuration")
      await waitForMarkdownResult(document, source: replacement.source)
      XCTAssertEqual(document.content(for: replacement).renderPlainText(), "Current configuration")
    }
  }

  @MainActor func testRetiredMarkdownWorkCannotReplaceContentOrClearNewPendingWork() async {
    let worker = ControlledMarkdownPreparation()
    let document = NativeMarkdownDocument(prepare: worker.prepare)
    defer { document.cancel(); worker.cancelRemaining() }
    let initial = markdownRequest("A"), remounted = markdownRequest("AB"), appended = markdownRequest("ABC")
    _ = document.content(for: initial)
    document.receive(initial)
    await waitForMarkdownWork(worker, started: 1)
    document.cancel()
    XCTAssertEqual(document.content(for: remounted).renderPlainText(), "AB",
      "Without active preparation a size-only read must not freeze an old prefix")
    document.receive(remounted)
    await waitForMarkdownWork(worker, started: 2)

    // This preparer deliberately returns after cancellation, like work that
    // already crossed a noncancellable native parsing boundary.
    worker.finish(0, markdown: "Retired content")
    await waitForMarkdownReturns(worker, count: 1)
    XCTAssertNil(document.currentSource)
    XCTAssertEqual(document.content(for: appended).renderPlainText(), "AB")
    XCTAssertEqual(document.fallbackParseCount, 2,
      "A retired result must not clear the current job and reenable repeated fallback parsing")
    document.receive(appended)
    worker.finish(1)
    await waitForMarkdownWork(worker, started: 3)
    XCTAssertEqual(document.currentSource, remounted.source)
    worker.finish(2)
    await waitForMarkdownResult(document, source: appended.source)
    XCTAssertEqual(document.content(for: appended).renderPlainText(), "ABC")
  }

  @MainActor func testMarkdownSizingReadsWithoutPreparationKeepTheirExactSource() {
    let document = NativeMarkdownDocument()
    for source in ["A", "AB", "AC", "AC final"] {
      XCTAssertEqual(document.content(for: markdownRequest(source)).renderPlainText(), source)
    }
    XCTAssertEqual(document.fallbackParseCount, 4)
    XCTAssertEqual(document.preparationCount, 0)
  }

  @MainActor func testCancelledMarkdownRetainsPreparedPrefixUntilRemountedPreparationAdvances() async {
    let worker = ControlledMarkdownPreparation()
    let document = NativeMarkdownDocument(prepare: worker.prepare)
    defer { document.cancel(); worker.cancelRemaining() }
    let initial = markdownRequest("A"), appended = markdownRequest("AB")
    _ = document.content(for: initial)
    document.receive(initial)
    await waitForMarkdownWork(worker, started: 1)
    worker.finish(0)
    await waitForMarkdownResult(document, source: initial.source)
    document.cancel()

    let fallbacks = document.fallbackParseCount, preparations = document.preparationCount
    for _ in 0..<20 {
      XCTAssertEqual(document.content(for: appended).renderPlainText(), "A",
        "A size-only read can reuse a compatible prepared prefix without reparsing or scheduling work")
    }
    XCTAssertEqual(document.fallbackParseCount, fallbacks)
    XCTAssertEqual(document.preparationCount, preparations)
    XCTAssertEqual(worker.requests, [initial])
    document.receive(appended)
    await waitForMarkdownWork(worker, started: 2)
    XCTAssertEqual(document.content(for: appended).renderPlainText(), "A")
    worker.finish(1)
    await waitForMarkdownResult(document, source: appended.source)
    XCTAssertEqual(document.content(for: appended).renderPlainText(), "AB")
    XCTAssertEqual(document.fallbackParseCount, fallbacks)
    XCTAssertEqual(worker.requests, [initial, appended])
  }

  private func markdownRequest(_ source: String, mode: NativeRichTextMode = .markdown,
    fontSize: Double = 16, color: String = "#202124") -> NativeRichTextRequest {
    .init(source: OpenUIString(source), mode: mode, sources: [], fontSize: fontSize, color: color)
  }

  @MainActor private func waitForMarkdownWork(_ worker: ControlledMarkdownPreparation, started count: Int) async {
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in worker.requests.count >= count }, object: nil)
    await fulfillment(of: [ready], timeout: 3)
  }

  @MainActor private func waitForMarkdownReturns(_ worker: ControlledMarkdownPreparation, count: Int) async {
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in worker.returnedCount >= count }, object: nil)
    await fulfillment(of: [ready], timeout: 3)
  }

  @MainActor private func waitForMarkdownResult(_ document: NativeMarkdownDocument, source: OpenUIString) async {
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in document.currentSource == source }, object: nil)
    await fulfillment(of: [ready], timeout: 3)
  }
}

/// Starts only when the document launches work. Tests choose exactly which
/// result returns, including stale work that ignores cancellation after entry.
@MainActor private final class ControlledMarkdownPreparation {
  private(set) var requests: [NativeRichTextRequest] = []
  private(set) var returnedCount = 0
  private var continuations: [Int: CheckedContinuation<NativePreparedMarkdown, Error>] = [:]

  func prepare(_ request: NativeRichTextRequest) async throws -> NativePreparedMarkdown {
    try Task.checkCancellation()
    let index = requests.count
    requests.append(request)
    let result: NativePreparedMarkdown = try await withCheckedThrowingContinuation { continuation in
      continuations[index] = continuation
    }
    returnedCount += 1
    return result
  }

  func finish(_ index: Int, markdown: String? = nil) {
    guard requests.indices.contains(index), let continuation = continuations.removeValue(forKey: index) else {
      XCTFail("No pending Markdown preparation at index \(index)")
      return
    }
    let request = requests[index]
    continuation.resume(returning: NativePreparedMarkdown(request: request,
      content: MarkdownContent(markdown ?? request.source.displayString)))
  }

  func cancelRemaining() {
    let pending = Array(continuations.values)
    continuations.removeAll()
    for continuation in pending { continuation.resume(throwing: CancellationError()) }
  }
}

extension StreamingTextPresentationTests {
  @MainActor func testCanonicalMarkdownPreparationCoalescesWithoutStarvingContinuousInput() async throws {
    let document = NativeMarkdownDocument()
    func request(_ text: String) -> NativeRichTextRequest {
      .init(source: OpenUIString(text), mode: .textContent, sources: [], fontSize: 16, color: "#202124")
    }
    document.receive(request("**Start**"))
    var final = ""
    for index in 1...100 {
      final = "**Start** " + String(repeating: "中文内容 ", count: index)
      document.receive(request(final))
    }
    let finalSource = OpenUIString(final)
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      document.currentSource == finalSource
    }, object: nil)
    await fulfillment(of: [ready], timeout: 5)
    XCTAssertEqual(document.currentSource, finalSource)
    XCTAssertLessThanOrEqual(document.preparationCount, 2,
      "One active snapshot and one latest pending snapshot, not 100 queued jobs")
    XCTAssertTrue(document.content(for: request(final)).renderPlainText().contains("中文内容"))
    document.cancel()
  }

  @MainActor func testRepeatedMarkdownSizingReadsReuseTheSameParsedFallback() {
    let document = NativeMarkdownDocument()
    let request = NativeRichTextRequest(source: "**Readable** before mount", mode: .markdown,
      sources: [], fontSize: 16, color: "#202124")
    for _ in 0..<100 { _ = document.content(for: request) }
    XCTAssertEqual(document.fallbackParseCount, 1)
    XCTAssertEqual(document.preparationCount, 0, "A read must not launch background preparation")
    XCTAssertNil(document.currentSource)
  }

  @MainActor func testMarkdownCorrectionRejectsEarlierPreparedResult() async {
    let document = NativeMarkdownDocument()
    func request(_ source: String) -> NativeRichTextRequest {
      .init(source: OpenUIString(source), mode: .textContent, sources: [], fontSize: 16, color: "#202124")
    }
    document.receive(request("Old content"))
    document.receive(request("Replacement"))
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      document.currentSource == "Replacement"
    }, object: nil)
    await fulfillment(of: [ready], timeout: 5)
    XCTAssertEqual(document.content(for: request("Replacement")).renderPlainText(), "Replacement")
    document.cancel()
    document.receive(request("After remount"))
    let remounted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      document.currentSource == "After remount"
    }, object: nil)
    await fulfillment(of: [remounted], timeout: 5)
    XCTAssertEqual(document.currentSource, "After remount")
    document.cancel()
  }
}


extension StreamingTextPresentationTests {
  @MainActor func testFormulaBudgetsRejectBeforeCreatingAWebViewJob() async {
    let renderer = NativeMathRenderer()
    for (tex, size, color) in [
      (String(repeating: "x", count: 16_385), CGFloat(16), "#202124"),
      ("x", CGFloat.infinity, "#202124"),
      ("x", CGFloat(0), "#202124"),
      ("x", CGFloat(16), "red; background:url(https://invalid.example)")
    ] {
      do { _ = try await renderer.image(for: .init(tex: tex, display: false), fontSize: size, color: color); XCTFail("Budget violation accepted") }
      catch { XCTAssertEqual((error as? URLError)?.code, .dataLengthExceedsMaximum) }
    }
    XCTAssertEqual(renderer.pendingRequestCount, 0)
    XCTAssertEqual(renderer.cachedPixelBytes, 0)
  }

  @MainActor func testIdenticalFormulaSubscribersShareWorkAndCanCancelIndependently() async {
    let renderer = NativeMathRenderer()
    let first = Task { try await renderer.image(for: .init(tex: "x + 1", display: true), fontSize: 16, color: "#202124") }
    let second = Task { try await renderer.image(for: .init(tex: "x + 1", display: true), fontSize: 16, color: "#202124") }
    let shared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in renderer.pendingSubscriberCount == 2 }, object: nil)
    await fulfillment(of: [shared], timeout: 3)
    XCTAssertEqual(renderer.pendingRequestCount, 1)
    first.cancel()
    do { _ = try await first.value; XCTFail("Cancelled subscriber returned an image") }
    catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertFalse(second.isCancelled)
    XCTAssertEqual(renderer.pendingRequestCount, 1)
    second.cancel()
    do { _ = try await second.value; XCTFail("Cancelled subscriber returned an image") }
    catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(renderer.pendingRequestCount, 0)
    renderer.cancel()
  }
}
