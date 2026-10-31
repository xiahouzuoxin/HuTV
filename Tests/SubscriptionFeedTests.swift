import XCTest
@testable import HuTV

private actor FeedClient: HTTPDataLoading {
    var list = "[]"
    var listRequests = 0
    func setList(_ value: String) { list = value }
    func count() -> Int { listRequests }
    func data(for request: URLRequest, maximumBytes: Int, additionalValidStatusCodes: Set<Int>) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let body: String
        if url.path == "/list.json" { listRequests += 1; body = list }
        else if url.path == "/broken" { throw URLError(.cannotConnectToHost) }
        else { body = #"{"class":[{"type_id":1,"type_name":"电影"}],"list":[]}"# }
        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

final class SubscriptionFeedTests: XCTestCase {
    private let feedURL = URL(string: "https://example.com/list.json")!
    private func entries(_ text: String) throws -> [BatchSubscriptionEntry] {
        try BatchSubscriptionList().decode(Data(text.utf8))
    }
    @MainActor func testFeedUpdatesURLPreservesIdentityAndPersists() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let client = FeedClient()
        let store = WarehouseStore(storageURL: file, loader: SubscriptionLoader(client: client), includeDefaults: false)
        let initial = try entries(#"[{"name":"A","api":"https://example.com/old"}]"#)
        _ = try await store.importOnlineBatch(initial, allEntries: initial, from: feedURL)
        let original = store.warehouses[0]
        await client.setList(#"[{"name":"A","api":"https://example.com/new"},{"name":"B","api":"https://example.com/b"}]"#)
        try await store.refreshFeed(id: store.feeds[0].id)
        XCTAssertEqual(store.warehouses.map(\.name), ["A", "B"])
        XCTAssertEqual(store.warehouses[0].id, original.id)
        XCTAssertEqual(store.warehouses[0].importedAt, original.importedAt)
        XCTAssertEqual(store.warehouses[0].configURL.path, "/new")
        let restored = WarehouseStore(storageURL: file, loader: SubscriptionLoader(client: client), includeDefaults: false)
        XCTAssertEqual(restored.feeds[0].members.count, 2)
        XCTAssertEqual(restored.warehouses.map(\.id), store.warehouses.map(\.id))
    }
    @MainActor func testRefreshRespectsDeselectionDeletionAndManualEdits() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let client = FeedClient()
        let store = WarehouseStore(storageURL: file, loader: SubscriptionLoader(client: client), includeDefaults: false)
        let json = #"[{"name":"A","api":"https://example.com/a"},{"name":"B","api":"https://example.com/b"},{"name":"C","api":"https://example.com/c"}]"#
        let initial = try entries(json)
        _ = try await store.importOnlineBatch(Array(initial.prefix(2)), allEntries: initial, from: feedURL)
        store.delete(id: store.warehouses[0].id)
        try await store.update(id: store.warehouses[0].id, name: "我的名称", address: "https://example.com/custom")
        await client.setList(json)
        try await store.refreshFeed(id: store.feeds[0].id)
        XCTAssertEqual(store.warehouses.count, 1)
        XCTAssertEqual(store.warehouses[0].name, "我的名称")
        XCTAssertEqual(store.warehouses[0].configURL.path, "/custom")
        XCTAssertEqual(store.feeds[0].excluded.count, 3)
    }
    @MainActor func testBadEndpointAndMalformedListKeepExistingSubscriptions() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let client = FeedClient()
        let store = WarehouseStore(storageURL: file, loader: SubscriptionLoader(client: client), includeDefaults: false)
        let initial = try entries(#"[{"name":"A","api":"https://example.com/old"}]"#)
        _ = try await store.importOnlineBatch(initial, allEntries: initial, from: feedURL)
        await client.setList(#"[{"name":"A","api":"https://example.com/broken"}]"#)
        try await store.refreshFeed(id: store.feeds[0].id)
        XCTAssertEqual(store.warehouses[0].configURL.path, "/old")
        XCTAssertNotNil(store.feeds[0].lastError)
        await client.setList("<html>error</html>")
        do { try await store.refreshFeed(id: store.feeds[0].id); XCTFail("Expected invalid JSON") } catch { }
        XCTAssertEqual(store.warehouses.count, 1)
        await client.setList("[]")
        try await store.refreshFeed(id: store.feeds[0].id)
        XCTAssertEqual(store.warehouses.count, 1, "Remote removal must not destroy local choices")
    }
    @MainActor func testExistingIndependentSubscriptionIsNotReaddedAfterDeletion() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let client = FeedClient()
        let store = WarehouseStore(storageURL: file, loader: SubscriptionLoader(client: client), includeDefaults: false)
        try await store.importURL("https://example.com/a", kind: .cms, name: "自己添加")
        let json = #"[{"name":"A","api":"https://example.com/a"}]"#
        let initial = try entries(json)
        _ = try await store.importOnlineBatch(initial, allEntries: initial, from: feedURL)
        XCTAssertTrue(store.feeds[0].members.isEmpty)
        store.delete(id: store.warehouses[0].id)
        await client.setList(json)
        try await store.refreshFeed(id: store.feeds[0].id)
        XCTAssertTrue(store.warehouses.isEmpty)
    }

    @MainActor func testChangingRefreshIntervalUsesLastAttemptAndRejectsInvalidValues() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let client = FeedClient()
        let store = WarehouseStore(storageURL: file, loader: SubscriptionLoader(client: client), includeDefaults: false)
        _ = try await store.importOnlineBatch([], allEntries: [], from: feedURL)
        let now = Date()
        await store.autoRefreshIfNeeded(now: now, intervalHours: 24)
        await store.autoRefreshIfNeeded(now: now.addingTimeInterval(7200), intervalHours: 24)
        var count = await client.count()
        XCTAssertEqual(count, 1)
        await store.autoRefreshIfNeeded(now: now.addingTimeInterval(7200), intervalHours: 1)
        count = await client.count()
        XCTAssertEqual(count, 2)
        await store.autoRefreshIfNeeded(now: now.addingTimeInterval(10800), intervalHours: 0)
        count = await client.count()
        XCTAssertEqual(count, 2)
        let cancelled = Task { await store.autoRefreshIfNeeded(now: now.addingTimeInterval(86400), intervalHours: 1) }
        cancelled.cancel()
        await cancelled.value
        count = await client.count()
        XCTAssertEqual(count, 2)
    }

    @MainActor func testAutoRefreshIsThrottledAndStoppedFeedsDoNotRun() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let client = FeedClient()
        let store = WarehouseStore(storageURL: file, loader: SubscriptionLoader(client: client), includeDefaults: false)
        let initial = try entries(#"[{"name":"A","api":"https://example.com/a"}]"#)
        _ = try await store.importOnlineBatch(initial, allEntries: initial, from: feedURL)
        let now = Date()
        await store.autoRefreshIfNeeded(now: now)
        await store.autoRefreshIfNeeded(now: now.addingTimeInterval(60))
        let count = await client.count()
        XCTAssertEqual(count, 1)
        let restored = WarehouseStore(storageURL: file, loader: SubscriptionLoader(client: client), includeDefaults: false)
        await restored.autoRefreshIfNeeded(now: now.addingTimeInterval(120))
        let afterRestore = await client.count()
        XCTAssertEqual(afterRestore, 1)
        await store.autoRefreshIfNeeded(now: now.addingTimeInterval(21601))
        let afterInterval = await client.count()
        XCTAssertEqual(afterInterval, 2)
        store.setFeedEnabled(store.feeds[0].id, enabled: false)
        try await store.refreshFeed(id: store.feeds[0].id)
        let afterDisabled = await client.count()
        XCTAssertEqual(afterDisabled, 2)
        store.removeFeed(store.feeds[0].id)
        XCTAssertTrue(store.feeds.isEmpty)
        XCTAssertEqual(store.warehouses.count, 1)
    }
}
