import XCTest
@testable import HuTV

private struct SearchFixtureProvider: ContentProvider {
    let id: String
    let delay: UInt64
    var fail = false
    var source: TVBoxSite { TVBoxSite(key: id, name: id, api: "https://example.com/api") }
    func categories() async throws -> [MediaCategory] { [] }
    func items(categoryID: String?, page: Int) async throws -> [MediaItem] { [] }
    func detail(id: String) async throws -> MediaDetail { throw ProviderError.invalidData }
    func search(keyword: String) async throws -> [MediaItem] {
        // Deliberately ignore cancellation to simulate a slow external source.
        try? await Task.sleep(nanoseconds: delay)
        if fail { throw ProviderError.invalidData }
        return [MediaItem(id: "\(id)|\(keyword)", sourceID: id, title: keyword, posterURL: nil, detailID: keyword)]
    }
}

final class HistorySearchTests: XCTestCase {
    private func target(sourceID: String = "source", episode: String = "1") -> WatchTarget {
        .vod(item: MediaItem(id: "\(sourceID)|movie", sourceID: sourceID, title: "电影", posterURL: nil, detailID: "movie"),
             source: TVBoxSite(key: sourceID, name: sourceID, api: "https://example.com/api"),
             episode: MediaEpisode(id: episode, name: episode, url: "https://example.com/\(episode).m3u8", line: "M3U8"))
    }

    @MainActor func testHistoryPersistenceDedupAndSourceIsolation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        let store = HistoryStore(storageURL: file)
        store.addSearch("  Movie  ")
        store.addSearch("Other")
        store.addSearch("movie")
        XCTAssertEqual(store.searches, ["movie", "Other"])
        store.record(target(), position: 50, duration: 200)
        store.record(target(sourceID: "other"), position: 10, duration: 200)
        store.record(target(episode: "2"), position: 80, duration: 200)
        XCTAssertEqual(store.records.count, 2)
        let restored = HistoryStore(storageURL: file)
        XCTAssertEqual(restored.searches, ["movie", "Other"])
        XCTAssertEqual(restored.records.first?.position, 80)
        XCTAssertEqual(restored.resumeRecord(sourceID: "source", detailID: "movie")?.position, 80)
        let wrongEpisode = MediaEpisode(id: "1", name: "1", url: "https://example.com/1.m3u8", line: "M3U8")
        XCTAssertNil(restored.resumeRecord(sourceID: "source", detailID: "movie", episode: wrongEpisode))
        if case .vod(_, _, let episode) = restored.records[0].target { XCTAssertEqual(episode.id, "2") }
        else { XCTFail("Expected a VOD record") }
        restored.removeRecord(restored.records[0].id)
        restored.clearSearches()
        restored.clearRecords()
        let cleared = HistoryStore(storageURL: file)
        XCTAssertTrue(cleared.searches.isEmpty)
        XCTAssertTrue(cleared.records.isEmpty)
    }

    @MainActor func testHistoryLimitsAndInvalidProgress() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = HistoryStore(storageURL: file)
        for value in 0..<35 { store.addSearch("\(value)") }
        XCTAssertEqual(store.searches.count, 30)
        store.record(target(), position: .nan, duration: 100)
        XCTAssertTrue(store.records.isEmpty)
        store.record(target(), position: 95, duration: 100)
        XCTAssertEqual(store.records[0].resumePosition, 0)
        store.record(target(), position: 20, duration: .infinity)
        XCTAssertEqual(store.records[0].duration, 0)
        XCTAssertEqual(store.records[0].resumePosition, 20)
    }

    @MainActor func testSearchKeepsSourceOrderAndSeparatesFailures() async {
        let model = SearchModel()
        let sources = [SearchSource(provider: SearchFixtureProvider(id: "slow", delay: 20_000_000), title: "慢源"),
                       SearchSource(provider: SearchFixtureProvider(id: "error", delay: 0, fail: true), title: "失败源")]
        await model.search("关键词", sources: sources)
        XCTAssertEqual(model.groups.map(\.id), ["slow", "error"])
        XCTAssertEqual(model.groups[0].items.first?.title, "关键词")
        XCTAssertNotNil(model.groups[1].error)
        XCTAssertFalse(model.groups.contains(where: \.isLoading))
    }

    @MainActor func testLateSearchCannotOverwriteNewerQueryOrReset() async {
        let model = SearchModel()
        let sources = [SearchSource(provider: SearchFixtureProvider(id: "slow", delay: 30_000_000), title: "源")]
        let first = Task { await model.search("旧关键词", sources: sources) }
        await Task.yield()
        await model.search("新关键词", sources: sources)
        await first.value
        XCTAssertEqual(model.groups[0].items.first?.title, "新关键词")
        let pending = Task { await model.search("待取消", sources: sources) }
        await Task.yield()
        model.reset()
        await pending.value
        XCTAssertFalse(model.hasSearched)
        XCTAssertTrue(model.groups.isEmpty)
    }
}
