import XCTest
@testable import HuTV

private struct RacingProvider: ContentProvider {
    let id = "race"
    var source: TVBoxSite { TVBoxSite(key: id, name: id, api: "https://example.com") }
    func categories() async throws -> [MediaCategory] { [] }
    func search(keyword: String) async throws -> [MediaItem] { [] }
    func items(categoryID: String?, page: Int) async throws -> [MediaItem] {
        // Ignore cancellation deliberately: the consumer must reject stale responses.
        if categoryID == "slow" || page > 1 { try? await Task.sleep(for: .milliseconds(100)) }
        let key = "\(categoryID ?? "initial")-\(page)"
        let item = MediaItem(id: key, sourceID: id, title: key, posterURL: nil, detailID: key)
        return [item, item]
    }
    func detail(id: String) async throws -> MediaDetail {
        return MediaDetail(id: id, title: id, posterURL: nil, summary: "", metadata: "", episodes: [
            MediaEpisode(id: "fresh1", name: "1", url: "https://example.com/fresh1.m3u8", line: "main"),
            MediaEpisode(id: "fresh2", name: "2", url: "https://example.com/fresh2.m3u8", line: "main")])
    }
}

final class OptimizationTests: XCTestCase {
    @MainActor func testOldCategoryCannotOverwriteNewSelection() async throws {
        let provider = RacingProvider(), model = SourceBrowserModel()
        await model.load(provider: provider)
        XCTAssertEqual(model.items.count, 1)
        model.select("slow", provider: provider)
        await Task.yield()
        model.select("fast", provider: provider)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.items.map(\.title), ["fast-1"])
        XCTAssertFalse(model.isLoadingItems)
    }

    @MainActor func testOldPaginationCannotMixWithNewCategory() async throws {
        let provider = RacingProvider(), model = SourceBrowserModel()
        await model.load(provider: provider)
        let page = Task { await model.loadNextPage(provider: provider) }
        while !model.isLoadingMore { await Task.yield() }
        model.select("fast", provider: provider)
        await page.value
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(model.items.map(\.title), ["fast-1"])
        XCTAssertEqual(model.page, 1)
        XCTAssertFalse(model.isLoadingMore)
    }

    @MainActor func testEpisodeSwitchUsesListedURLsAndPreservesOpening() {
        let provider = RacingProvider()
        let item = MediaItem(id: "movie", sourceID: "race", title: "movie", posterURL: nil, detailID: "movie")
        let episodes = [MediaEpisode(id: "1", name: "1", url: "https://example.com/listed1", line: "main"),
                        MediaEpisode(id: "2", name: "2", url: "https://example.com/listed2", line: "main")]
        let session = OnDemandPlaybackSession(item: item, source: provider.source, episodes: episodes,
            selected: episodes[0], position: 300, episodeStart: 120)
        let oldRevision = session.revision
        XCTAssertTrue(session.advance(after: "1"))
        XCTAssertEqual(session.queue.current.url, episodes[1].url)
        XCTAssertEqual(session.startPosition, 120)
        XCTAssertNotEqual(session.revision, oldRevision)
        XCTAssertFalse(session.advance(after: "1"))
        XCTAssertFalse(session.advance(after: "2"))
        XCTAssertFalse(session.acceptProgress(301, duration: 600, revision: oldRevision))
        XCTAssertTrue(session.retreat(before: "2"))
        XCTAssertEqual(session.queue.current.url, episodes[0].url)
        XCTAssertEqual(session.position, 120)
        XCTAssertFalse(session.retreat(before: "1"))
    }

    func testExplicitResolutionStillGetsFreshURL() async throws {
        let provider = RacingProvider()
        let item = MediaItem(id: "movie", sourceID: "race", title: "movie", posterURL: nil, detailID: "movie")
        let episode = MediaEpisode(id: "1", name: "1", url: "https://example.com/old", line: "main")
        let resolved = try await EpisodeResolver.resolve(item: item, source: provider.source, episode: episode, provider: provider)
        XCTAssertEqual(resolved.1.url, "https://example.com/fresh1.m3u8")
    }

    func testStallMonitoringExcludesPauseBackgroundAndSeek() {
        var monitor = PlaybackStallMonitor()
        XCTAssertFalse(monitor.stalled(position: 10, now: 0, monitoring: true))
        XCTAssertFalse(monitor.stalled(position: 10, now: 29, monitoring: true))
        XCTAssertTrue(monitor.stalled(position: 10, now: 30, monitoring: true))
        XCTAssertFalse(monitor.stalled(position: 11, now: 31, monitoring: true))
        XCTAssertFalse(monitor.stalled(position: 11, now: 100, monitoring: false))
        XCTAssertFalse(monitor.stalled(position: 11, now: 200, monitoring: true))
        XCTAssertFalse(monitor.stalled(position: 11, now: 229, monitoring: true))
    }

    @MainActor func testDeferredHistoryFlushAndResetOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        let history = HistoryStore(storageURL: file)
        let provider = RacingProvider()
        let item = MediaItem(id: "movie", sourceID: "race", title: "movie", posterURL: nil, detailID: "movie")
        let episode = MediaEpisode(id: "1", name: "1", url: "https://example.com/1", line: "main")
        for position in 0..<20 {
            history.record(.vod(item: item, source: provider.source, episode: episode), position: Double(position), duration: 100, deferred: true)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        history.flushPending(); history.waitForPendingWrites()
        XCTAssertEqual(HistoryStore(storageURL: file).records.first?.position, 19)
        history.record(.vod(item: item, source: provider.source, episode: episode), position: 40, duration: 100, deferred: true)
        history.flushPending()
        try history.clearAll()
        history.waitForPendingWrites()
        XCTAssertTrue(HistoryStore(storageURL: file).records.isEmpty)
    }
}
