import Foundation
import SwiftUI
import XCTest
@testable import SwiftLang

final class ResourceCacheBudgetTests: XCTestCase {
  @MainActor func testSharedImageBudgetEvictsLeastRecentlyUsedEntryAcrossDocuments() throws {
    let budget = NativeResourceCacheBudget(maximumCost: 8, maximumCount: 128)
    let first = NativeMediaCache(budget: budget), second = NativeMediaCache(budget: budget)
    let loader = OpenUIURLSessionResourceLoader()
    let a = key("a", loader: loader), b = key("b", loader: loader)
    let c = key("c", loader: loader), d = key("d", loader: loader)
    first.insert(entry(cost: 2, loader: loader), for: a)
    first.insert(entry(cost: 2, loader: loader), for: b)
    let displayed = try XCTUnwrap(first[b])
    second.insert(entry(cost: 2, loader: loader), for: c)
    first.markPresented(a)
    XCTAssertTrue(try XCTUnwrap(first[a]).wasPresented)
    second.insert(entry(cost: 4, loader: loader), for: d)

    XCTAssertNil(first[b], "The shared budget must evict the oldest hit, even in another document")
    XCTAssertNotNil(first[a]); XCTAssertNotNil(second[c]); XCTAssertNotNil(second[d])
    XCTAssertEqual(budget.retainedCost, 8)
    XCTAssertEqual(budget.retainedCount, 3)
    XCTAssertEqual(displayed.cost, 2, "Eviction drops the cache reference, not a renderer's existing entry")
  }

  @MainActor func testImageCacheRetainsItsLocalLRULimitAndHigherResolutionEntry() throws {
    let budget = NativeResourceCacheBudget(maximumCost: 64 * 1024 * 1024, maximumCount: 128)
    let cache = NativeMediaCache(budget: budget), loader = OpenUIURLSessionResourceLoader()
    let keys = (0..<9).map { key(String($0), loader: loader) }
    for candidate in keys.prefix(8) { cache.insert(entry(cost: 4, pixels: 100, loader: loader), for: candidate) }
    XCTAssertNotNil(cache[keys[0]])
    cache.insert(entry(cost: 4, pixels: 100, loader: loader), for: keys[8])
    XCTAssertNil(cache[keys[1]], "The per-document eight-entry limit also uses reads, not insertion order")
    XCTAssertNotNil(cache[keys[0]])
    XCTAssertEqual(budget.retainedCount, 8)

    cache.insert(entry(cost: 1, pixels: 50, loader: loader), for: keys[0])
    XCTAssertEqual(try XCTUnwrap(cache[keys[0]]).decodedPixelSize, 100)
    cache.insert(entry(cost: 32 * 1024 * 1024 + 1, pixels: 200, loader: loader), for: keys[0])
    XCTAssertEqual(try XCTUnwrap(cache[keys[0]]).cost, 4, "Oversize replacements preserve the usable entry")
    XCTAssertEqual(budget.retainedCost, 32)
  }

  @MainActor func testImageReplacementUpdatesSharedCostWithoutDiscardingValidOversizeTargets() throws {
    let budget = NativeResourceCacheBudget(maximumCost: 5, maximumCount: 128)
    let first = NativeMediaCache(budget: budget), second = NativeMediaCache(budget: budget)
    let loader = OpenUIURLSessionResourceLoader()
    let a = key("a", loader: loader), b = key("b", loader: loader), c = key("c", loader: loader)
    first.insert(entry(cost: 2, pixels: 100, loader: loader), for: a)
    second.insert(entry(cost: 2, pixels: 100, loader: loader), for: b)
    first.insert(entry(cost: 6, pixels: 200, loader: loader), for: a)
    first.insert(entry(cost: 6, pixels: 200, loader: loader), for: c)
    XCTAssertEqual(try XCTUnwrap(first[a]).cost, 2)
    XCTAssertNotNil(second[b]); XCTAssertNil(first[c])
    XCTAssertEqual(budget.retainedCost, 4, "A value larger than the whole pool must not evict other entries")

    first.insert(entry(cost: 4, pixels: 200, loader: loader), for: a)
    XCTAssertNil(second[b])
    XCTAssertEqual(try XCTUnwrap(first[a]).cost, 4)
    XCTAssertEqual(budget.retainedCost, 4)
    first.insert(entry(cost: 1, pixels: 300, loader: loader), for: a)
    second.insert(entry(cost: 4, loader: loader), for: c)
    XCTAssertNotNil(first[a]); XCTAssertNotNil(second[c])
    XCTAssertEqual(budget.retainedCost, 5, "Replacing an entry must remove its previous cost")
  }

  @MainActor func testImageCacheKeepsPerDocumentCostWithinLargerSharedPool() {
    let budget = NativeResourceCacheBudget(maximumCost: 64 * 1024 * 1024, maximumCount: 128)
    let cache = NativeMediaCache(budget: budget), loader = OpenUIURLSessionResourceLoader()
    let keys = (0..<3).map { key(String($0), loader: loader) }
    for candidate in keys { cache.insert(entry(cost: 16 * 1024 * 1024, loader: loader), for: candidate) }
    XCTAssertNil(cache[keys[0]])
    XCTAssertNotNil(cache[keys[1]]); XCTAssertNotNil(cache[keys[2]])
    XCTAssertEqual(budget.retainedCount, 2)
    XCTAssertEqual(budget.retainedCost, 32 * 1024 * 1024,
      "The shared pool must not let one document exceed its existing pixel-cache allowance")
  }

  @MainActor func testSharedBudgetDoesNotKeepImageCacheOrItsResourceOwnerAlive() {
    let budget = NativeResourceCacheBudget(maximumCost: 8, maximumCount: 8)
    var cache: NativeMediaCache? = NativeMediaCache(budget: budget)
    weak var releasedCache = cache
    weak var releasedLoader: OpenUIURLSessionResourceLoader?
    do {
      let loader = OpenUIURLSessionResourceLoader()
      releasedLoader = loader
      cache?.insert(entry(cost: 4, loader: loader), for: key("retired", loader: loader))
    }
    XCTAssertNotNil(releasedLoader, "A live entry keeps its request owner identity valid")
    XCTAssertEqual(budget.retainedCost, 4)
    cache = nil
    XCTAssertNil(releasedCache)
    XCTAssertNil(releasedLoader, "The shared budget must not retain the cache's values or transport")
    XCTAssertEqual(budget.retainedCost, 0)
    XCTAssertEqual(budget.retainedCount, 0)
  }

  @MainActor func testTrimmingImageBudgetPreservesRequestIdentityAndDocumentGeneration() throws {
    let budget = NativeResourceCacheBudget(maximumCost: 8, maximumCount: 8)
    let cache = NativeMediaCache(budget: budget), loader = OpenUIURLSessionResourceLoader()
    let request = key("signed", loader: loader)
    cache.insert(entry(cost: 4, loader: loader), for: request)
    cache.retainRequestSnapshot(request, for: "presentation", owner: loader)
    let displayed = try XCTUnwrap(cache[request]), generation = cache.generation
    budget.removeAll()
    XCTAssertNil(cache[request])
    XCTAssertEqual(cache.generation, generation)
    XCTAssertEqual(cache.requestSnapshot(for: "presentation"), request)
    XCTAssertEqual(displayed.size, CGSize(width: 100, height: 100))
    cache.insert(displayed, for: request)
    XCTAssertNotNil(cache[request], "The same valid document can repopulate a trimmed cache")
  }

  @MainActor func testSharedImageBudgetPreservesCurrentRequestPolicyOnReplacement() throws {
    let budget = NativeResourceCacheBudget(maximumCost: 8, maximumCount: 8)
    let cache = NativeMediaCache(budget: budget), loader = MutableCacheLoader()
    let request = key("same-address", loader: loader)
    let original = entry(cost: 4, pixels: 1_024, loader: loader)
    cache.insert(original, for: request)
    loader.resourceLimits.maximumImagePixelSize = 128
    XCTAssertNil(cache[request], "An old bitmap must not satisfy a changed resource policy")

    cache.insert(entry(cost: 2, pixels: 128, loader: loader), for: request)
    XCTAssertEqual(try XCTUnwrap(cache[request]).decodedPixelSize, 128,
      "The stale higher-resolution entry must not block a valid smaller replacement")
    cache.insert(original, for: request)
    XCTAssertEqual(try XCTUnwrap(cache[request]).decodedPixelSize, 128,
      "A result prepared under old limits must not replace the current pixels")
    XCTAssertEqual(budget.retainedCost, 2)

    budget.removeAll()
    loader.authorizationScopeID = "replacement-account"
    cache.insert(entry(cost: 2, loader: loader), for: request)
    let other = MutableCacheLoader()
    cache.insert(entry(cost: 2, loader: other), for: key("owner", loader: loader))
    XCTAssertEqual(budget.retainedCount, 0,
      "Shared admission must retain the current scope and request-owner checks")
  }

  @MainActor private func key(_ name: String, loader: any OpenUIResourceLoading) -> NativeResourceRequestID {
    NativeResourceRequestID(request: URLRequest(url: URL(string: "https://cache.test/" + name)!),
      loader: ObjectIdentifier(loader), attempt: 0, authorizationScope: loader.authorizationScopeID)
  }
  @MainActor private func entry(cost: Int, pixels: Int = 100, loader: any OpenUIResourceLoading) -> NativeMediaCache.Entry {
    NativeMediaCache.Entry(image: Image(systemName: "photo"), size: CGSize(width: 100, height: 100),
      cost: cost, resourceOwner: loader, decodedPixelSize: pixels)
  }
}

/// This fixture is used only by synchronous MainActor cache operations.
private final class MutableCacheLoader: OpenUIResourceLoading {
  var resourceLimits = OpenUIResourceLimits()
  var authorizationScopeID = "initial-account"
  func request(for source: String, relativeTo baseURL: URL?) -> URLRequest? {
    URL(string: source, relativeTo: baseURL).map { URLRequest(url: $0) }
  }
  func data(for request: URLRequest) async throws -> Data { throw URLError(.resourceUnavailable) }
}
