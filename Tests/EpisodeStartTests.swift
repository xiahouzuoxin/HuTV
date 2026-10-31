import XCTest
import UIKit
@testable import HuTV

final class EpisodeStartTests: XCTestCase {
    private func item(_ source: String = "source", detail: String = "series") -> MediaItem {
        MediaItem(id: source + detail, sourceID: source, title: "同名剧", posterURL: nil, detailID: detail)
    }
    @MainActor func testStartPersistsSeparatelyFromHistoryAndIsScopedBySourceAndSeries() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = HistoryStore(storageURL: file)
        store.setEpisodeStart(120.8, for: item())
        store.setEpisodeStart(.nan, for: item())
        store.clearRecords()
        let restored = HistoryStore(storageURL: file)
        XCTAssertEqual(restored.episodeStart(for: item()), 120)
        XCTAssertEqual(restored.episodeStart(for: item("other")), 0)
        XCTAssertEqual(restored.episodeStart(for: item(detail: "different")), 0)
        restored.setEpisodeStart(135, for: item())
        XCTAssertEqual(restored.episodeStart(for: item()), 135)
        restored.setEpisodeStart(0, for: item())
        XCTAssertEqual(HistoryStore(storageURL: file).episodeStart(for: item()), 0)
    }
    @MainActor func testInitialResumeNextPreviousAndSourceSwitchUseStartPolicy() {
        let episodes = ["1", "2"].map { MediaEpisode(id: $0, name: $0, url: "https://example.com/\($0).mp4", line: "A") }
        let source = TVBoxSite(key: "source", name: "源", api: "https://example.com/api")
        let session = OnDemandPlaybackSession(item: item(), source: source, episodes: episodes,
            selected: episodes[0], position: 20, episodeStart: 120)
        XCTAssertEqual(session.startPosition, 120)
        session.setEpisodeStart(130)
        XCTAssertEqual(session.startPosition, 120, "Recording the marker must not restart current playback")
        XCTAssertTrue(session.advance(after: "1"))
        XCTAssertEqual(session.startPosition, 130)
        XCTAssertTrue(session.retreat(before: "2"))
        XCTAssertEqual(session.startPosition, 130)
        _ = session.acceptProgress(600, duration: 1000, revision: session.revision)
        session.select(item: item(), source: source, episodes: episodes, episode: episodes[1], keepPosition: true, episodeStart: 120)
        XCTAssertEqual(session.startPosition, 600)
        session.select(item: item("other"), source: source, episodes: episodes, episode: episodes[0], keepPosition: false)
        XCTAssertEqual(session.startPosition, 0)
    }
    @MainActor func testButtonRecordsAndLongPressDoesNotRecordAgainOnRelease() {
        let button = EpisodeStartButton(frame: .zero)
        var recorded = 0, cleared = 0
        button.onRecord = { recorded += 1 }
        button.onClear = { cleared += 1 }
        button.canRecord = true
        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(recorded, 1)
        button.sendActions(for: .touchDown)
        button.clearFromLongPress()
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(cleared, 1)
        XCTAssertEqual(recorded, 1)
        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(recorded, 2)
        button.canRecord = false
        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(recorded, 2)
        button.clearFromLongPress()
        XCTAssertEqual(cleared, 2)
    }

    @MainActor func testReadsOlderHistoryWithoutStartMarkers() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(#"{"searches":["测试"],"records":[]}"#.utf8).write(to: file)
        let history = HistoryStore(storageURL: file)
        XCTAssertEqual(history.searches, ["测试"])
        XCTAssertEqual(history.episodeStart(for: item()), 0)
        XCTAssertNil(history.persistenceError)
    }
}
