import XCTest
@testable import HuTV

private actor HotClient: HTTPDataLoading {
    var calls = 0
    var fail = false
    func setFailure() { fail = true }
    func count() -> Int { calls }
    func data(for request: URLRequest, maximumBytes: Int, additionalValidStatusCodes: Set<Int>) async throws -> (Data, HTTPURLResponse) {
        calls += 1
        if fail { throw URLError(.notConnectedToInternet) }
        let type = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "type" }!.value!
        if type == "movie" { try? await Task.sleep(for: .milliseconds(50)) }
        let body = "{\"subjects\":[{\"id\":\"\(type)\",\"title\":\"\(type)\",\"rate\":\"8.2\"},{\"id\":\"\(type)\",\"title\":\"duplicate\"}]}"
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

final class DoubanHotTests: XCTestCase {

    @MainActor func testTagsLoadOnDemandAndPersistForOneDay() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = HotClient()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = DoubanHotModel(client: client, diskCache: DoubanHotCache(directory: directory), now: { date })
        let initial = await client.count()
        XCTAssertEqual(initial, 0, "Creating the model must not prefetch any tags")
        await first.load(.movie)
        await first.load(.movie, tag: "科幻")
        await first.load(.movie, tag: "科幻")
        await first.load(.tv)
        let afterTags = await client.count()
        XCTAssertEqual(afterTags, 3, "Only explicitly selected type/tag combinations are fetched")

        let reopened = DoubanHotModel(client: client, diskCache: DoubanHotCache(directory: directory), now: { date.addingTimeInterval(86_399) })
        await reopened.load(.movie, tag: "科幻")
        let afterReopen = await client.count()
        XCTAssertEqual(afterReopen, 3, "A new model must reuse the on-disk cache")
        XCTAssertFalse(reopened.items.isEmpty)

        let expired = DoubanHotModel(client: client, diskCache: DoubanHotCache(directory: directory), now: { date.addingTimeInterval(86_400) })
        await expired.load(.movie, tag: "科幻")
        let afterExpiry = await client.count()
        XCTAssertEqual(afterExpiry, 4)
        await expired.load(.movie, tag: "不存在的分类")
        let afterInvalid = await client.count()
        XCTAssertEqual(afterInvalid, 4)
    }

    func testFlexibleRatingAndOptionalImages() throws {
        let item = try JSONDecoder().decode(DoubanHotItem.self, from: Data(#"{"id":123,"title":"影片","rate":8.5,"cover":"javascript:bad","url":"https://movie.douban.com/subject/123/"}"#.utf8))
        XCTAssertEqual(item.id, "123")
        XCTAssertEqual(item.rating?.value, 8.5)
        XCTAssertNil(item.cover)
        XCTAssertEqual(item.url?.host, "movie.douban.com")
        let unrated = try JSONDecoder().decode(DoubanHotItem.self, from: Data(#"{"id":"1","title":"新片","rate":""}"#.utf8))
        XCTAssertNil(unrated.rating)
    }

    @MainActor func testCacheDeduplicationAndFailure() async {
        let client = HotClient()
        let model = DoubanHotModel(client: client, diskCache: DoubanHotCache(directory: nil))
        await model.load(.movie)
        await model.load(.movie)
        let count = await client.count()
        XCTAssertEqual(count, 1)
        XCTAssertEqual(model.items.count, 1)
        await client.setFailure()
        model.invalidate(.movie)
        await model.load(.movie)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.items.first?.id, "movie")
        XCTAssertFalse(model.isLoading)
    }

    @MainActor func testOldCategoryCannotOverwriteLatest() async {
        let model = DoubanHotModel(client: HotClient(), diskCache: DoubanHotCache(directory: nil))
        let old = Task { await model.load(.movie) }
        try? await Task.sleep(for: .milliseconds(10))
        await model.load(.tv)
        await old.value
        XCTAssertEqual(model.items.first?.id, "tv")
        XCTAssertFalse(model.isLoading)
    }
}
