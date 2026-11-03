import XCTest
@testable import HuTV

final class EpisodeQueueTests: XCTestCase {
    private func episode(_ id: String, line: String = "A") -> MediaEpisode {
        MediaEpisode(id: id, name: id, url: "https://example.com/\(id).m3u8", line: line)
    }
    func testM3U8LinesComeFirstWithoutChangingEpisodeOrEquivalentLineOrder() {
        let episodes = [
            MediaEpisode(id: "mp4", name: "1", url: "https://example.com/1.mp4?next=.m3u8", line: "M3U8 名称但实际 MP4"),
            MediaEpisode(id: "b2", name: "2", url: "https://example.com/2.M3U8?token=x", line: "B"),
            MediaEpisode(id: "b1", name: "1", url: "https://example.com/1.m3u8", line: "B"),
            MediaEpisode(id: "a1", name: "1", url: "https://example.com/a.m3u8", line: "A"),
            MediaEpisode(id: "web", name: "1", url: "https://example.com/watch", line: "网页")
        ]
        let ordered = MediaEpisode.prioritized(episodes)
        XCTAssertEqual(ordered.map(\.id), ["b2", "b1", "a1", "mp4", "web"])
        XCTAssertTrue(ordered[0].isM3U8)
        XCTAssertFalse(episodes[0].isM3U8)
        let manual = EpisodeQueue(episodes: ordered, selected: episodes[0])
        XCTAssertEqual(manual.current.id, "mp4")
        XCTAssertEqual(MediaEpisode.prioritized(Array(episodes.prefix(1))).map(\.id), ["mp4"])
    }

    func testCMSDetailPrioritizesActualM3U8URLs() async throws {
        let source = TVBoxSite(key: "priority", name: "priority", api: "https://example.com/api")
        let detail = try await StandardCMSProvider(id: "priority", source: source, client: PriorityDetailClient()).detail(id: "1")
        XCTAssertEqual(detail.episodes.map(\.line), ["HLS", "HLS", "MP4"])
        XCTAssertEqual(detail.episodes.map(\.name), ["第1集", "第2集", "第1集"])
        XCTAssertTrue(detail.episodes.first!.isM3U8)
    }

    func testAdvancesInSourceOrderWithoutCrossingLinesOrWrapping() {
        let one = episode("1"), two = episode("2"), other = episode("other", line: "B")
        var queue = EpisodeQueue(episodes: [one, other, two], selected: one)
        XCTAssertEqual(queue.current.id, "1")
        XCTAssertTrue(queue.advance(after: "1"))
        XCTAssertEqual(queue.current.id, "2")
        XCTAssertFalse(queue.hasNext)
        XCTAssertFalse(queue.advance(after: "2"))
        XCTAssertEqual(queue.current.id, "2")
    }
    func testDuplicateOrStaleEndEventDoesNotSkipEpisode() {
        let episodes = [episode("1"), episode("2"), episode("3")]
        var queue = EpisodeQueue(episodes: episodes, selected: episodes[0])
        XCTAssertTrue(queue.advance(after: "1"))
        XCTAssertFalse(queue.advance(after: "1"))
        XCTAssertEqual(queue.current.id, "2")
    }
    func testSelectedEpisodeAndSingleEpisodeFallback() {
        let episodes = [episode("1"), episode("2")]
        let queue = EpisodeQueue(episodes: episodes, selected: episodes[1])
        XCTAssertEqual(queue.current.id, "2")
        XCTAssertFalse(queue.hasNext)
        let fallback = EpisodeQueue(episodes: [], selected: episodes[0])
        XCTAssertEqual(fallback.current.id, "1")
        XCTAssertFalse(fallback.hasNext)
    }
    func testPreviousStopsAtFirstAndRejectsStaleEpisode() {
        let episodes = [episode("1"), episode("2"), episode("3")]
        var queue = EpisodeQueue(episodes: episodes, selected: episodes[1])
        XCTAssertTrue(queue.hasPrevious)
        XCTAssertTrue(queue.retreat(before: "2"))
        XCTAssertEqual(queue.current.id, "1")
        XCTAssertFalse(queue.hasPrevious)
        XCTAssertFalse(queue.retreat(before: "1"))
        XCTAssertFalse(queue.retreat(before: "2"))
        XCTAssertTrue(queue.advance(after: "1"))
        XCTAssertEqual(queue.current.id, "2")
    }

    @MainActor func testSwitchingSourcesKeepsPositionButRejectsOldProgressEvenWithSameEpisodeID() {
        let first = episode("1"), second = episode("2")
        let item = MediaItem(id: "old/1", sourceID: "old", title: "影片", posterURL: nil, detailID: "1")
        let source = TVBoxSite(key: "old", name: "原源", api: "https://example.com/old")
        let playback = OnDemandPlaybackSession(item: item, source: source, episodes: [first, second], selected: first, position: 20)
        let oldRevision = playback.revision
        XCTAssertTrue(playback.acceptProgress(120, duration: 1000, revision: oldRevision))
        let newItem = MediaItem(id: "new/9", sourceID: "new", title: "影片新版", posterURL: nil, detailID: "9")
        let newSource = TVBoxSite(key: "new", name: "新源", api: "https://example.com/new")
        playback.select(item: newItem, source: newSource, episodes: [first, second], episode: first, keepPosition: true)
        XCTAssertEqual(playback.startPosition, 120)
        XCTAssertEqual(playback.item.sourceID, "new")
        XCTAssertEqual(playback.source.name, "新源")
        XCTAssertNotEqual(playback.revision, oldRevision)
        XCTAssertFalse(playback.acceptProgress(999, duration: 1000, revision: oldRevision))
        XCTAssertEqual(playback.position, 120)
        XCTAssertTrue(playback.advance(after: first.id))
        XCTAssertEqual(playback.queue.current.id, second.id)
        XCTAssertEqual(playback.startPosition, 0)
    }

    @MainActor func testSwitchingLinesUsesSelectedLineAndCanStartFromZero() {
        let one = episode("1"), alternate = episode("b1", line: "B"), next = episode("b2", line: "B")
        let item = MediaItem(id: "1", sourceID: "source", title: "影片", posterURL: nil, detailID: "1")
        let source = TVBoxSite(key: "source", name: "源", api: "https://example.com/api")
        let playback = OnDemandPlaybackSession(item: item, source: source,
            episodes: [one, alternate, next], selected: one, position: 80)
        playback.select(item: item, source: source, episodes: [one, alternate, next], episode: alternate, keepPosition: false)
        XCTAssertEqual(playback.startPosition, 0)
        XCTAssertEqual(playback.queue.episodes.map(\.id), [alternate.id, next.id])
        XCTAssertTrue(playback.advance(after: alternate.id))
        XCTAssertFalse(playback.advance(after: next.id))
        XCTAssertTrue(playback.retreat(before: next.id))
        XCTAssertEqual(playback.queue.current.id, alternate.id)
    }

}

private struct PriorityDetailClient: HTTPDataLoading {
    func data(for request: URLRequest, maximumBytes: Int, additionalValidStatusCodes: Set<Int>) async throws -> (Data, HTTPURLResponse) {
        let body = #"{"list":[{"vod_id":1,"vod_name":"测试","vod_play_from":"MP4$$$HLS","vod_play_url":"第1集$https://example.com/1.mp4$$$第1集$https://example.com/1.M3U8?token=x#第2集$https://example.com/2.m3u8"}]}"#
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
