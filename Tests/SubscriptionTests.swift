import XCTest
@testable import HuTV

private struct FixtureHTTPClient: HTTPDataLoading {
    let body: String
    func data(for request: URLRequest, maximumBytes: Int,
              additionalValidStatusCodes: Set<Int>) async throws -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                                        httpVersion: nil, headerFields: nil)!)
    }
}

final class SubscriptionTests: XCTestCase {
    private let url = URL(string: "https://example.com/source")!
    private let cms = #"{"class":[{"type_id":1,"type_name":"电影"}],"list":[]}"#
    private let m3u = "#EXTM3U\n#EXTINF:-1 group-title=\"新闻\",测试频道\nhttps://example.com/live.m3u8"

    func testMediaURLClassificationDoesNotTreatWebPagesAsDirectMedia() {
        XCTAssertTrue(MediaEpisode(id: "1", name: "1", url: "https://example.com/a.m3u8?token=x", line: "m3u8").isDirectMedia)
        XCTAssertFalse(MediaEpisode(id: "2", name: "1", url: "https://example.com/share/abc", line: "cloud").isDirectMedia)
    }

    func testCMSImportCreatesNativeSearchableSource() async throws {
        let value = try await SubscriptionLoader(client: FixtureHTTPClient(body: cms))
            .load(from: url, kind: .cms, name: "我的点播")
        XCTAssertEqual(value.kind, .cms)
        XCTAssertEqual(value.name, "我的点播")
        XCTAssertEqual(value.config.sites.first?.api, url.absoluteString)
        XCTAssertEqual(value.config.sites.first?.runtime, .nativeAPI)
        XCTAssertNotNil(ContentProviderFactory.make(for: value.config.sites[0]))
        XCTAssertTrue(value.config.lives.isEmpty)
    }

    func testLiveImportAndRefreshPreserveIdentityAndName() async throws {
        let loader = SubscriptionLoader(client: FixtureHTTPClient(body: m3u))
        let first = try await loader.load(from: url, kind: .live, name: "我的直播")
        let refreshed = try await loader.load(from: url, kind: first.kind, replacing: first)
        XCTAssertEqual(refreshed.id, first.id)
        XCTAssertEqual(refreshed.importedAt, first.importedAt)
        XCTAssertEqual(refreshed.name, "我的直播")
        XCTAssertEqual(refreshed.config.lives.first?.url, url.absoluteString)
        XCTAssertTrue(refreshed.config.sites.isEmpty)
    }

    func testWrongContentIsRejectedForEachProtocol() async {
        for (kind, body) in [(SubscriptionKind.cms, "<html>error</html>"),
                              (.cms, #"{"error":"not authorized"}"#),
                              (.cms, #"{"class":"invalid"}"#),
                              (.live, "<html>not a playlist</html>"),
                              (.tvbox, #"{"sites":[],"lives":[]}"#)] {
            do {
                _ = try await SubscriptionLoader(client: FixtureHTTPClient(body: body))
                    .load(from: url, kind: kind)
                XCTFail("Accepted invalid \(kind) content")
            } catch { }
        }
    }

    func testTVBoxAcceptsLiveOnlyConfiguration() async throws {
        let value = try await SubscriptionLoader(client: FixtureHTTPClient(
            body: #"{"lives":[{"name":"直播","url":"https://example.com/list.m3u"}]}"#))
            .load(from: url, kind: .tvbox)
        XCTAssertTrue(value.config.sites.isEmpty)
        XCTAssertEqual(value.config.lives.count, 1)
    }

    @MainActor func testStorePersistsProtocolAndRefreshesUsingSameProtocol() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("subscriptions.json")
        let loader = SubscriptionLoader(client: FixtureHTTPClient(body: m3u))
        let store = WarehouseStore(storageURL: file, loader: loader, includeDefaults: false)
        try await store.importURL(url.absoluteString, kind: .live, name: "频道")
        try await store.importURL(url.absoluteString, kind: .live, name: "频道更新")
        XCTAssertEqual(store.warehouses.count, 1)
        let restored = WarehouseStore(storageURL: file, loader: loader, includeDefaults: false)
        XCTAssertEqual(restored.warehouses.first?.kind, .live)
        XCTAssertEqual(restored.warehouses.first?.name, "频道更新")
        try await restored.refresh(id: restored.warehouses[0].id)
        XCTAssertEqual(restored.warehouses.first?.config.lives.count, 1)
    }
    @MainActor func testDefaultSourcesSeedOnceAndRespectDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("subscriptions.json")
        let store = WarehouseStore(storageURL: file)
        XCTAssertEqual(store.warehouses.count, 16)
        XCTAssertEqual(store.warehouses.filter { $0.kind == .cms && $0.config.sites.first?.runtime == .nativeAPI }.count, 13)
        XCTAssertEqual(store.warehouses.filter { $0.kind == .live && !$0.config.lives.isEmpty }.count, 3)
        store.addDefaultSubscriptions()
        XCTAssertEqual(store.warehouses.count, 16)
        store.delete(at: IndexSet(integer: 0))
        let restored = WarehouseStore(storageURL: file)
        XCTAssertEqual(restored.warehouses.count, 15)
        restored.addDefaultSubscriptions()
        XCTAssertEqual(restored.warehouses.count, 16)
    }

    @MainActor func testAddingPresetsPreservesExistingSubscriptionsWithoutDuplicates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("subscriptions.json")
        var existing = DefaultSubscriptions.make()[0]
        existing.name = "我的暴风"
        existing.configURL = URL(string: "https://bfzyapi.com/api.php/provide/vod")!
        try JSONEncoder().encode([existing]).write(to: file)
        let store = WarehouseStore(storageURL: file)
        XCTAssertEqual(store.warehouses.count, 16)
        XCTAssertEqual(store.warehouses.first?.id, existing.id)
        XCTAssertEqual(store.warehouses.first?.name, "我的暴风")
    }

    @MainActor func testPresetUpgradeAddsOnlyNewPresetsAndDoesNotRestoreDeletedOnes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("subscriptions.json")
        let oldPresets = Array(DefaultSubscriptions.make().prefix(4).dropFirst())
        struct OldSnapshot: Encodable {
            let warehouses: [Warehouse]
            let defaultsInstalled: Bool
        }
        try JSONEncoder().encode(OldSnapshot(warehouses: oldPresets, defaultsInstalled: true)).write(to: file)
        let store = WarehouseStore(storageURL: file)
        XCTAssertEqual(store.warehouses.count, 15)
        XCTAssertFalse(store.warehouses.contains { $0.name == "暴风资源" })
        XCTAssertEqual(store.warehouses.first?.id, oldPresets.first?.id)
        store.delete(at: IndexSet(integer: 3))
        let restored = WarehouseStore(storageURL: file)
        XCTAssertEqual(restored.warehouses.count, 14)
        XCTAssertFalse(restored.warehouses.contains { $0.name == "量子资源" })
        restored.addDefaultSubscriptions()
        XCTAssertEqual(restored.warehouses.count, 16)
    }

    @MainActor func testSubscriptionOrderAndDeletionSurviveRestartAndRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("subscriptions.json")
        let loader = SubscriptionLoader(client: FixtureHTTPClient(body: cms))
        let store = WarehouseStore(storageURL: file, loader: loader)
        let original = store.warehouses.map(\.id)
        let cmsIDs = store.warehouses.filter { $0.kind == .cms }.map(\.id)
        let liveIDs = store.warehouses.filter { $0.kind == .live }.map(\.id)
        store.move(from: IndexSet([0, 2]), to: cmsIDs.count, kind: .cms)
        let expected = cmsIDs.enumerated().filter { ![0, 2].contains($0.offset) }.map(\.element)
            + [cmsIDs[0], cmsIDs[2]] + liveIDs
        XCTAssertEqual(store.warehouses.map(\.id), expected)
        let deleted = expected[1]
        store.delete(id: deleted)
        let remaining = expected.filter { $0 != deleted }
        let restored = WarehouseStore(storageURL: file, loader: loader)
        XCTAssertEqual(restored.warehouses.map(\.id), remaining)
        try await restored.refresh(id: original[0])
        XCTAssertEqual(restored.warehouses.map(\.id), remaining)
        let existing = try XCTUnwrap(restored.warehouses.first { $0.id == original[0] })
        try await restored.importURL(existing.configURL.absoluteString, kind: existing.kind, name: "重命名")
        XCTAssertEqual(restored.warehouses.map(\.id), remaining)
        XCTAssertEqual(WarehouseStore(storageURL: file).warehouses.map(\.id), remaining)
    }

    @MainActor func testVersionTwoUpgradeKeepsOrderAndDeletionAndAddsSixNewPresetsOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("subscriptions.json")
        let all = DefaultSubscriptions.make()
        var retained = [all[7], all[1]]
        retained[0].name = "我的无尽"
        struct Snapshot: Encodable {
            let warehouses: [Warehouse]
            let defaultsInstalled = true
            let installedPresetVersion = 2
        }
        try JSONEncoder().encode(Snapshot(warehouses: retained)).write(to: file)
        let store = WarehouseStore(storageURL: file)
        XCTAssertEqual(Array(store.warehouses.prefix(2)).map(\.id), retained.map(\.id))
        XCTAssertEqual(store.warehouses.first?.name, "我的无尽")
        XCTAssertEqual(store.warehouses.count, 8)
        XCTAssertFalse(store.warehouses.contains { $0.name == "量子资源" })
        XCTAssertEqual(Set(store.warehouses.dropFirst(2).map(\.name)),
                       Set(["极速资源", "光速资源", "ikun资源", "U酷资源", "闪电资源", "IPTV-org 新闻直播"]))
        store.delete(id: store.warehouses.last!.id)
        let restored = WarehouseStore(storageURL: file)
        XCTAssertEqual(restored.warehouses.map(\.id), store.warehouses.map(\.id))
    }

    @MainActor func testGroupedSortingAndDeletionUseGroupOffsets() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("subscriptions.json")
        let presets = DefaultSubscriptions.make()
        let cms = presets.filter { $0.kind == .cms }
        let live = presets.filter { $0.kind == .live }
        let mixed = [cms[0], live[0], cms[1], live[1], cms[2]]
        try JSONEncoder().encode(mixed).write(to: file)
        let store = WarehouseStore(storageURL: file, includeDefaults: false)
        store.move(from: IndexSet(integer: 0), to: 3, kind: .cms)
        XCTAssertEqual(store.warehouses.map(\.id), [cms[1], live[0], cms[2], live[1], cms[0]].map(\.id))
        store.move(from: IndexSet(integer: 1), to: 0, kind: .live)
        XCTAssertEqual(store.warehouses.filter { $0.kind == .live }.map(\.id), [live[1], live[0]].map(\.id))
        store.delete(at: IndexSet(integer: 0), kind: .live)
        XCTAssertEqual(store.warehouses.map(\.id), [cms[1], cms[2], live[0], cms[0]].map(\.id))
        let restored = WarehouseStore(storageURL: file, includeDefaults: false)
        XCTAssertEqual(restored.warehouses.map(\.id), store.warehouses.map(\.id))
    }

}
