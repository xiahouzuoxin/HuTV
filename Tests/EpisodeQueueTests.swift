import XCTest
@testable import HuTV

final class EpisodeQueueTests: XCTestCase {
    private func episode(_ id: String, line: String = "A") -> MediaEpisode {
        MediaEpisode(id: id, name: id, url: "https://example.com/\(id).m3u8", line: line)
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
