import XCTest
@testable import HuTV

final class PlaybackScrubTests: XCTestCase {
    func testPreviewSurvivesOldProgressUntilSeekCompletes() throws {
        var state = PlaybackScrubState()
        state.begin(at: 10)
        state.update(to: 120)
        XCTAssertEqual(state.displayedPosition(current: 11, duration: 300), 120)
        let request = try XCTUnwrap(state.commit())
        XCTAssertFalse(state.isDragging)
        XCTAssertEqual(request.position, 120)
        XCTAssertEqual(state.displayedPosition(current: 12, duration: 300), 120)
        XCTAssertTrue(state.complete(request.id))
        XCTAssertEqual(state.displayedPosition(current: 121, duration: 300), 121)
    }

    func testNewDragIgnoresOlderSeekCompletion() throws {
        var state = PlaybackScrubState()
        state.begin(at: 10)
        state.update(to: 100)
        let first = try XCTUnwrap(state.commit())
        state.begin(at: 11)
        XCTAssertEqual(state.displayedPosition(current: 11, duration: 300), 100)
        state.update(to: 200)
        let second = try XCTUnwrap(state.commit())
        XCTAssertFalse(state.complete(first.id))
        XCTAssertEqual(state.displayedPosition(current: 100, duration: 300), 200)
        XCTAssertTrue(state.complete(second.id))
        XCTAssertEqual(state.displayedPosition(current: 200, duration: 300), 200)
    }

    func testBindingBeforeBeginAndReset() throws {
        var state = PlaybackScrubState()
        state.update(to: 90)
        state.begin(at: 10)
        XCTAssertEqual(state.displayedPosition(current: 10, duration: 300), 90)
        let request = try XCTUnwrap(state.commit())
        XCTAssertNil(state.commit(), "Only one seek per release")
        state.reset()
        XCTAssertFalse(state.complete(request.id))
        XCTAssertEqual(state.displayedPosition(current: 10, duration: 300), 10)
    }

    func testFailedSeekCanReturnToActualPositionAndClampsPreview() throws {
        var state = PlaybackScrubState()
        state.begin(at: 10)
        state.update(to: 400)
        XCTAssertEqual(state.displayedPosition(current: 10, duration: 300), 300)
        let request = try XCTUnwrap(state.commit())
        state.complete(request.id)
        XCTAssertEqual(state.displayedPosition(current: 10, duration: 300), 10)
    }
}
