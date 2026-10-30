import XCTest
@testable import HuTV

private struct BatchFixtureClient: HTTPDataLoading {
    func data(for request: URLRequest, maximumBytes: Int, additionalValidStatusCodes: Set<Int>) async throws -> (Data, HTTPURLResponse) {
        if request.url!.host == "bad.example" { throw URLError(.cannotConnectToHost) }
        let body = request.url!.pathExtension == "m3u" ? "#EXTM3U\n#EXTINF:-1,频道\nhttps://example.com/live.m3u8" : #"{"class":[{"type_id":1,"type_name":"电影"}],"list":[]}"#
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

final class BatchSubscriptionTests: XCTestCase {
    func testGitHubShapeSupportsCommentsTrailingCommasAndUnsupportedSchemes() throws {
        let text = #"""
        [
          {"name":"点播","api":"https://example.com/api?value=//keep",}, // comment
          {"name":"直播","url":"https://example.com/live.m3u?token=a"},
          {"name":"无扩展直播","api":"https://example.com/list","kind":"live"},
          {"name":"聚合","api":"https://example.com/config","type":"tvbox"},
          {"name":"爬虫","api":"cms://ddys"},
          12,
        ]
        """#
        let entries = try BatchSubscriptionList().decode(Data(("\u{FEFF}" + text).utf8))
        XCTAssertEqual(entries.count, 6)
        XCTAssertEqual(entries[0].address, "https://example.com/api?value=//keep")
        XCTAssertEqual(entries.prefix(4).compactMap(\.kind), [.cms, .live, .live, .tvbox])
        XCTAssertNotNil(entries[4].issue)
        XCTAssertNotNil(entries[5].issue)
    }

    func testGitHubURLNormalizationAndMalformedPayloads() throws {
        XCTAssertEqual(try BatchSubscriptionList.downloadURL("https://github.com/cms-player/vod-source/blob/main/source.json?raw=true").absoluteString,
                       "https://raw.githubusercontent.com/cms-player/vod-source/main/source.json")
        let reader = BatchSubscriptionList()
        for text in ["<html>Not JSON</html>", "{}", "[", "[/*unterminated"] {
            XCTAssertThrowsError(try reader.decode(Data(text.utf8)))
        }
        XCTAssertThrowsError(try reader.decode(JSONSerialization.data(withJSONObject: Array(repeating: [:] as [String: String], count: 201))))
        XCTAssertThrowsError(try reader.decode(Data(repeating: 32, count: BatchSubscriptionList.maximumBytes + 1)))
        XCTAssertThrowsError(try BatchSubscriptionList.downloadURL("file:///tmp/list.json"))
    }

    @MainActor func testBatchImportKeepsExistingOrderAndNameAndReportsPartialFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("subscriptions.json")
        let loader = SubscriptionLoader(client: BatchFixtureClient())
        let store = WarehouseStore(storageURL: file, loader: loader, includeDefaults: false)
        try await store.importURL("https://example.com/existing/", kind: .cms, name: "我的名称")
        let originalID = store.warehouses[0].id
        let entries = try BatchSubscriptionList().decode(Data(#"""
        [
          {"name":"不覆盖名称","api":"https://example.com/existing"},
          {"name":"新点播","api":"https://example.com/new"},
          {"name":"重复新项","api":"https://example.com/new/"},
          {"name":"失败","api":"https://bad.example/api"},
          {"name":"频道","api":"https://example.com/live.m3u"},
          {"name":"跳过","api":"cms://test"}
        ]
        """#.utf8))
        let results = try await store.importBatch(entries)
        XCTAssertEqual(results.map(\.status), [.skipped, .added, .skipped, .failed, .added, .skipped])
        XCTAssertEqual(store.warehouses.map(\.name), ["我的名称", "新点播", "频道"])
        XCTAssertEqual(store.warehouses[0].id, originalID)
        let restored = WarehouseStore(storageURL: file, includeDefaults: false)
        XCTAssertEqual(restored.warehouses.map(\.id), store.warehouses.map(\.id))
    }

    @MainActor func testCancelledBatchDoesNotCommitPartialSubscriptions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WarehouseStore(storageURL: directory.appendingPathComponent("subscriptions.json"),
                                   loader: SubscriptionLoader(client: BatchFixtureClient()), includeDefaults: false)
        let entries = try BatchSubscriptionList().decode(Data(#"[{"api":"https://example.com/new"}]"#.utf8))
        let task = Task { try await store.importBatch(entries) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled import must fail") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(store.warehouses.isEmpty)
    }
    @MainActor func testBatchDeduplicationDoesNotDiscardDifferentQueryTokens() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WarehouseStore(storageURL: directory.appendingPathComponent("subscriptions.json"),
                                   loader: SubscriptionLoader(client: BatchFixtureClient()), includeDefaults: false)
        let entries = try BatchSubscriptionList().decode(Data(#"[{"api":"https://EXAMPLE.com/api?token=a/"},{"api":"https://example.com/api?token=a"}]"#.utf8))
        let results = try await store.importBatch(entries)
        XCTAssertEqual(results.map(\.status), [.added, .added])
        XCTAssertEqual(store.warehouses.count, 2)
    }

}
