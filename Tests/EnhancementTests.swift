import XCTest
@testable import HuTV

private actor SearchProbe {
    var active = 0
    var peak = 0
    var started = 0
    func run() async throws {
        active += 1; started += 1; peak = max(peak, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(35))
    }
}
private struct LimitedProvider: ContentProvider {
    let id: String
    let probe: SearchProbe
    var source: TVBoxSite { TVBoxSite(key: id, name: id, api: "https://example.com") }
    func categories() async throws -> [MediaCategory] { [] }
    func items(categoryID: String?, page: Int) async throws -> [MediaItem] { [] }
    func detail(id: String) async throws -> MediaDetail { throw ProviderError.invalidData }
    func search(keyword: String) async throws -> [MediaItem] {
        try await probe.run()
        return [MediaItem(id: id, sourceID: id, title: keyword, posterURL: nil, detailID: id)]
    }
}
private struct DetailClient: HTTPDataLoading {
    func data(for request: URLRequest, maximumBytes: Int, additionalValidStatusCodes: Set<Int>) async throws -> (Data, HTTPURLResponse) {
        let body = #"{"list":[{"vod_id":1,"vod_name":"测试","vod_year":2025,"vod_score":7.2,"vod_douban_score":"8.6","vod_lang":"汉语","vod_pubdate":"2025-01-01","vod_duration":"45分钟","vod_area":"中国","vod_director":"导演","vod_actor":"甲,乙","type_name":"剧情","vod_content":"<p>简介</p>","vod_play_from":"线路","vod_play_url":"第一集$https://example.com/1.m3u8"}]}"#
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

final class EnhancementTests: XCTestCase {

    func testRatingValidationAndLegacyHistoryDecoding() throws {
        for value in ["", "0", "-1", "11", "NaN", "暂无评分"] {
            XCTAssertNil(MediaRating(raw: value, source: "源评分"))
        }
        let vod = try JSONDecoder().decode(CMSVod.self, from: Data(#"{"vod_score":"7.5","vod_douban_score":0}"#.utf8))
        XCTAssertEqual(vod.rating?.value, 7.5)
        XCTAssertEqual(vod.rating?.source, "源评分")
        let missing = try JSONDecoder().decode(CMSVod.self, from: Data(#"{"vod_score":null}"#.utf8))
        XCTAssertNil(missing.rating)
        let item = try JSONDecoder().decode(MediaItem.self, from: Data(#"{"id":"a","sourceID":"s","title":"旧记录","detailID":"1"}"#.utf8))
        XCTAssertNil(item.rating)
        var rated = item
        rated.rating = vod.rating
        XCTAssertEqual(try JSONDecoder().decode(MediaItem.self, from: JSONEncoder().encode(rated)), rated)
    }

    func testDetailMetadataAndMissingFields() async throws {
        let provider = StandardCMSProvider(id: "test", source: TVBoxSite(key: "test", name: "test", api: "https://example.com"), client: DetailClient())
        let detail = try await provider.detail(id: "1")
        XCTAssertEqual(detail.rating?.value, 8.6)
        XCTAssertEqual(detail.language, "汉语")
        XCTAssertEqual(detail.releaseDate, "2025-01-01")
        XCTAssertEqual(detail.runningTime, "45分钟")
        let items = try await provider.items(categoryID: nil, page: 1)
        XCTAssertEqual(items.first?.rating, detail.rating)
        XCTAssertEqual(detail.director, "导演")
        XCTAssertEqual(detail.actors, "甲,乙")
        XCTAssertEqual(detail.category, "剧情")
        XCTAssertEqual(detail.metadata, "2025 · 中国")
        XCTAssertEqual(detail.summary, "简介")
        XCTAssertEqual(detail.episodes.count, 1)
        let empty = try JSONDecoder().decode(CMSVod.self, from: Data(#"{"vod_id":2,"vod_name":"旧源","vod_actor":null}"#.utf8))
        XCTAssertEqual(empty.actors, "")
        XCTAssertEqual(empty.director, "")
    }

    @MainActor func testSearchLimitsConcurrencyAndCompletesAllSources() async {
        let probe = SearchProbe()
        let sources = (0..<9).map { SearchSource(provider: LimitedProvider(id: "\($0)", probe: probe), title: "\($0)") }
        let model = SearchModel()
        await model.search("test", sources: sources, concurrency: 2)
        let peak = await probe.peak
        let started = await probe.started
        XCTAssertEqual(peak, 2)
        XCTAssertEqual(started, 9)
        XCTAssertEqual(model.groups.filter { !$0.isLoading && $0.items.count == 1 }.count, 9)
    }

    @MainActor func testCancelledSearchDoesNotStartQueuedSources() async {
        let probe = SearchProbe()
        let sources = (0..<20).map { SearchSource(provider: LimitedProvider(id: "\($0)", probe: probe), title: "\($0)") }
        let model = SearchModel()
        let task = Task { await model.search("test", sources: sources, concurrency: 2) }
        while await probe.started < 2 { await Task.yield() }
        task.cancel()
        await task.value
        let started = await probe.started
        XCTAssertEqual(started, 2)
    }

    func testForcedAspectFitsBothOrientations() {
        for container in [CGSize(width: 390, height: 220), CGSize(width: 844, height: 390)] {
            for (mode, ratio) in [(PlaybackScaling.widescreen, 16.0 / 9), (.standard, 4.0 / 3)] {
                let frame = mode.frame(in: container)
                XCTAssertLessThanOrEqual(frame.width, container.width)
                XCTAssertLessThanOrEqual(frame.height, container.height)
                XCTAssertEqual(frame.width / frame.height, ratio, accuracy: 0.001)
            }
        }
        XCTAssertEqual(PlaybackScaling.crop.gravity, .resizeAspectFill)
        XCTAssertEqual(PlaybackScaling.fit.gravity, .resizeAspect)
        XCTAssertEqual(PlaybackScaling.stretch.gravity, .resize)
    }

    @MainActor func testResetPersistsEmptyStoresAndDoesNotReseedDefaults() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let subscriptions = directory.appendingPathComponent("subscriptions.json")
        let historyFile = directory.appendingPathComponent("history.json")
        let store = WarehouseStore(storageURL: subscriptions)
        XCTAssertFalse(store.warehouses.isEmpty)
        let history = HistoryStore(storageURL: historyFile)
        let item = MediaItem(id: "x", sourceID: "x", title: "x", posterURL: nil, detailID: "x")
        history.addSearch("test")
        history.setEpisodeStart(120, for: item)
        try history.clearAll()
        try store.clearAll()
        history.retire(); store.retire()
        // A disappearing old player or an outstanding task must not write data back.
        history.addSearch("late")
        store.addDefaultSubscriptions()
        let restored = WarehouseStore(storageURL: subscriptions)
        XCTAssertTrue(restored.warehouses.isEmpty)
        XCTAssertTrue(restored.feeds.isEmpty)
        let saved = HistoryStore(storageURL: historyFile)
        XCTAssertTrue(saved.searches.isEmpty)
        XCTAssertTrue(saved.records.isEmpty)
        XCTAssertTrue(saved.episodeStarts.isEmpty)
    }

    func testPreferenceResetAndCacheClearAreScoped() {
        let suite = "HuTV.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(8, forKey: "search.concurrency")
        defaults.set(true, forKey: "subscriptions.autoRefresh")
        defaults.set("preserved", forKey: "unrelated")
        AppMaintenance.resetPreferences(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: "search.concurrency"))
        XCTAssertNil(defaults.object(forKey: "subscriptions.autoRefresh"))
        XCTAssertEqual(defaults.string(forKey: "unrelated"), "preserved")
        let cache = URLCache(memoryCapacity: 100_000, diskCapacity: 0)
        let url = URL(string: "https://example.com/cache")!
        let request = URLRequest(url: url)
        cache.storeCachedResponse(CachedURLResponse(response: URLResponse(url: url, mimeType: "text/plain", expectedContentLength: 3, textEncodingName: nil), data: Data("abc".utf8)), for: request)
        XCTAssertNotNil(cache.cachedResponse(for: request))
        AppMaintenance.clearCache(cache: cache)
        XCTAssertNil(cache.cachedResponse(for: request))
    }
}
