import AVFoundation
import XCTest
import UIKit
@testable import HuTV

final class PlaybackTests: XCTestCase {
    func testGestureBoundsAndDirection() {
        XCTAssertEqual(PlaybackGestureMath.seekTarget(start: 100, delta: 30, duration: 300), 130)
        XCTAssertEqual(PlaybackGestureMath.seekTarget(start: 10, delta: -50, duration: 300), 0)
        XCTAssertLessThan(PlaybackGestureMath.seekTarget(start: 290, delta: 50, duration: 300), 300)
        XCTAssertEqual(PlaybackGestureMath.level(start: 0.5, verticalFraction: -0.2), 0.7, accuracy: 0.001)
        XCTAssertEqual(PlaybackGestureMath.level(start: 0.5, verticalFraction: 2), 0)
        XCTAssertEqual(PlaybackGestureMath.level(start: 0.5, verticalFraction: -2), 1)
    }

    @MainActor func testAwakeOwnershipSurvivesOverlappingPlayersAndRestoresSetting() {
        var disabled = false
        let manager = ScreenAwakeManager(read: { disabled }, write: { disabled = $0 })
        let old = manager.acquire(), new = manager.acquire()
        XCTAssertTrue(disabled)
        manager.release(old)
        XCTAssertTrue(disabled)
        manager.release(old)
        XCTAssertTrue(disabled)
        manager.release(new)
        XCTAssertFalse(disabled)
        disabled = true
        let token = manager.acquire()
        manager.release(token)
        XCTAssertTrue(disabled)
    }

    @MainActor func testStopAndReopenLocalMediaRestoresProgressAndDetachesOldItem() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.mov")
        try await makeVideo(url)
        let originalIdleTimer = UIApplication.shared.isIdleTimerDisabled
        let controller = PlaybackController()
        var positions: [Double] = []
        let first = Task { await controller.start(resource: PlaybackResource(url: url), position: 0, buffer: 30,
            onProgress: { position, _ in positions.append(position) }, onEnded: nil) }
        try await waitUntilReady(controller)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        controller.togglePlay()
        controller.setRate(1.5)
        XCTAssertEqual(controller.player?.defaultRate, 1.5)
        XCTAssertEqual(controller.player?.rate, 0, "Changing speed while paused must not resume playback")
        controller.togglePlay()
        XCTAssertEqual(controller.player?.rate, 1.5)
        controller.setRate(1)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(controller.bufferedRanges.isEmpty)
        let oldSeek = Task { await controller.seek(to: 0.5) }
        await Task.yield()
        let latestSeek = Task { await controller.seek(to: 1.25) }
        await oldSeek.value
        await latestSeek.value
        XCTAssertNil(controller.errorMessage)
        let oldPlayer = controller.player
        controller.stop()
        first.cancel()
        await first.value
        XCTAssertNil(oldPlayer?.currentItem)
        XCTAssertEqual(UIApplication.shared.isIdleTimerDisabled, originalIdleTimer)
        XCTAssertGreaterThanOrEqual(positions.last ?? 0, 1)
        let saved = positions.last!
        positions = []
        let second = Task { await controller.start(resource: PlaybackResource(url: url), position: saved, buffer: 30,
            onProgress: { position, _ in positions.append(position) }, onEnded: nil) }
        try await waitUntilReady(controller)
        XCTAssertFalse(controller.player === oldPlayer)
        XCTAssertGreaterThanOrEqual(controller.position, 1)
        XCTAssertTrue(positions.allSatisfy { $0 >= 1 })
        controller.stop()
        second.cancel()
        await second.value
    }

    @MainActor func testVLCPlaysSeeksEndsAndCleansUp() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("vlc.mov")
        try await makeVideo(url)
        let controller = PlaybackController()
        controller.vlcDrawable.frame = CGRect(x: 0, y: 100, width: 128, height: 128)
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first!
        let host = UIViewController()
        let root = window.rootViewController!
        root.addChild(host)
        host.view.frame = CGRect(x: 0, y: 100, width: 128, height: 128)
        root.view.addSubview(host.view)
        host.didMove(toParent: root)
        host.view.addSubview(controller.vlcDrawable)
        defer {
            controller.stop()
            controller.vlcDrawable.removeFromSuperview()
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
        }
        var ended = false
        var progress: Double = 0
        let task = Task {
            await controller.start(resource: PlaybackResource(url: url), position: 1.25, buffer: 30,
                onProgress: { seconds, _ in progress = seconds }, onEnded: { ended = true }, engine: .vlc)
        }
        try await waitUntilReady(controller)
        XCTAssertNotNil(controller.vlcPlayer)
        controller.setRate(1.5)
        XCTAssertEqual(controller.vlcPlayer?.rate, 1.5)
        controller.setRate(1)
        XCTAssertGreaterThanOrEqual(controller.position, 0.25)
        for _ in 0..<100 {
            if ended { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(ended)
        XCTAssertGreaterThan(progress, 0)
        controller.stop()
        task.cancel()
        await task.value
        XCTAssertNil(controller.vlcPlayer)
    }

    @MainActor private func waitUntilReady(_ controller: PlaybackController) async throws {
        for _ in 0..<100 {
            if controller.ready { return }
            if let error = controller.errorMessage { XCTFail(error); throw ProviderError.invalidData }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Local media did not become ready. VLC state=\(controller.vlcPlayer?.state.rawValue ?? -1), time=\(controller.position), length=\(controller.duration), playing=\(controller.isPlaying)")
        controller.stop()
        throw ProviderError.invalidData
    }

    private func makeVideo(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                         kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ProviderError.invalidData }
        writer.startSession(atSourceTime: .zero)
        var optionalBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &optionalBuffer)
        let buffer = try XCTUnwrap(optionalBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 0, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for frame in 0..<90 {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw writer.error ?? ProviderError.invalidData }
                try await Task.sleep(for: .milliseconds(2))
            }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
                throw writer.error ?? ProviderError.invalidData
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: 3, preferredTimescale: 30))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ProviderError.invalidData }
    }
}
