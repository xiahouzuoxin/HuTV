import AVFoundation
import Network
import UIKit
import XCTest
@testable import HuTV

/// Serves only bundled synthetic assets over loopback for real HLS variant discovery.
private final class QualityHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "HuTV.quality-fixture")
    private let files: [String: Data]
    private var startFinished = false

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        let folder = try XCTUnwrap(Bundle(for: PlaybackQualityTests.self).resourceURL?.appendingPathComponent("Fixtures/Quality"))
        files = try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { ["m3u8", "ts"].contains($0.pathExtension) }
            .map { ("/" + $0.lastPathComponent, try Data(contentsOf: $0)) })
    }

    func start() async throws -> URL {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.receive(connection, data: Data())
        }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, !self.startFinished else { return }
                switch state {
                case .ready:
                    self.startFinished = true
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(self.listener.port!.rawValue)/master.m3u8")!)
                case .failed(let error):
                    self.startFinished = true; continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }
    func stop() { listener.cancel() }
    private func receive(_ connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] chunk, _, complete, error in
            guard let self else { connection.cancel(); return }
            let request = data + (chunk ?? Data())
            if request.range(of: Data("\r\n\r\n".utf8)) == nil {
                if complete || error != nil || request.count > 32768 { connection.cancel() }
                else { self.receive(connection, data: request) }
                return
            }
            let path = String(data: request, encoding: .utf8)?.components(separatedBy: " ").dropFirst().first ?? ""
            let body = self.files[path] ?? Data()
            let mime = path.hasSuffix(".m3u8") ? "application/vnd.apple.mpegurl" : "video/mp2t"
            let status = self.files[path] == nil ? "404 Not Found" : "200 OK"
            let header = "HTTP/1.1 \(status)\r\nContent-Type: \(mime)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}

final class PlaybackQualityTests: XCTestCase {
    func testChoicesRequireDistinctVideoResolutionsAndDeduplicateBitrates() {
        let low = PlaybackQualityOption(width: 640, height: 360, peakBitRate: 500000)
        let duplicate = PlaybackQualityOption(width: 640, height: 360, peakBitRate: 800000)
        let high = PlaybackQualityOption(width: 1920, height: 1080, peakBitRate: 4000000)
        let audio = PlaybackQualityOption(width: 0, height: 0, peakBitRate: 128000)
        XCTAssertTrue(PlaybackQualityOption.choices([low, duplicate, audio]).isEmpty)
        let options = PlaybackQualityOption.choices([high, low, audio, duplicate])
        XCTAssertEqual(options.map(\.label), ["360p", "1080p"])
        XCTAssertEqual(options.first?.peakBitRate, 800000)
        XCTAssertEqual(options.first?.menuLabel, "最高 360p")
        let disabled = PlaybackQualityOption(width: 320, height: 180, peakBitRate: 0, videoTrackIndex: -1)
        XCTAssertFalse(PlaybackQualityOption.choices([low, high, disabled]).contains(disabled))
    }

    @MainActor func testRealHLSDiscoveryAppliesAndClearsLimitsWithoutReplacingOrResumingPlayer() async throws {
        let server = try QualityHTTPServer()
        let url = try await server.start()
        defer { server.stop() }
        let controller = PlaybackController()
        let playback = Task {
            await controller.start(resource: PlaybackResource(url: url), position: 0, buffer: 0,
                                   onProgress: nil, onEnded: nil)
        }
        defer { controller.stop(); playback.cancel() }
        for _ in 0..<150 {
            if controller.ready && !controller.qualityOptions.isEmpty { break }
            if let error = controller.errorMessage { XCTFail(error); break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(controller.ready)
        XCTAssertEqual(controller.qualityOptions.map(\.label), ["180p", "360p"])
        XCTAssertNil(controller.selectedQualityID)
        let item = try XCTUnwrap(controller.player?.currentItem)
        controller.player?.pause()
        let lower = try XCTUnwrap(controller.qualityOptions.first)
        controller.selectQuality(lower.id)
        XCTAssertTrue(item === controller.player?.currentItem)
        XCTAssertEqual(item.preferredMaximumResolution, CGSize(width: 320, height: 180))
        XCTAssertEqual(item.preferredPeakBitRate, 300000)
        XCTAssertEqual(controller.player?.rate, 0)
        XCTAssertEqual(controller.qualityLabel, "最高 180p")
        controller.selectQuality(nil)
        XCTAssertEqual(item.preferredMaximumResolution, .zero)
        XCTAssertEqual(item.preferredPeakBitRate, 0)
        XCTAssertNil(controller.selectedQualityID)
        XCTAssertEqual(controller.player?.rate, 0)
        controller.stop()
        XCTAssertTrue(controller.qualityOptions.isEmpty)
        XCTAssertEqual(controller.qualityLabel, "自动")
    }
    @MainActor func testPausedAVSeekStaysPausedAndCanResume() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent("Fixtures/Quality/pause-controls.mp4"))
        let controller = PlaybackController()
        let task = Task {
            await controller.start(resource: PlaybackResource(url: url), position: 0, buffer: 0,
                                   onProgress: nil, onEnded: nil)
        }
        defer { controller.stop(); task.cancel() }
        for _ in 0..<100 {
            if controller.ready { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(controller.ready)
        controller.togglePlay()
        XCTAssertTrue(controller.isPaused)
        await controller.seek(to: 10)
        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(controller.position, 10, accuracy: 1)
        XCTAssertEqual(controller.player?.rate, 0)
        await controller.seek(to: controller.position - 10)
        XCTAssertEqual(controller.position, 0, accuracy: 1)
        controller.togglePlay()
        XCTAssertFalse(controller.isPaused)
    }

    @MainActor func testStartBeyondEpisodeDurationFallsBackToBeginning() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent("Fixtures/Quality/pause-controls.mp4"))
        let controller = PlaybackController()
        let task = Task {
            await controller.start(resource: PlaybackResource(url: url), position: 120, buffer: 0,
                                   onProgress: nil, onEnded: nil)
        }
        defer { controller.stop(); task.cancel() }
        for _ in 0..<100 {
            if controller.ready || controller.errorMessage != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(controller.ready)
        XCTAssertNil(controller.errorMessage)
        XCTAssertLessThan(controller.position, 5)
    }

    @MainActor func testVLCUsesRealVideoTracksAndRestoresDefault() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent("Fixtures/Quality/multi.mkv"))
        let controller = PlaybackController()
        controller.vlcDrawable.frame = CGRect(x: 0, y: 100, width: 128, height: 128)
        let window = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first)
        window.rootViewController?.view.addSubview(controller.vlcDrawable)
        let task = Task {
            await controller.start(resource: PlaybackResource(url: url), position: 0, buffer: 0,
                                   onProgress: nil, onEnded: nil, engine: .vlc)
        }
        defer { controller.stop(); task.cancel(); controller.vlcDrawable.removeFromSuperview() }
        for _ in 0..<100 {
            if controller.ready && controller.qualityOptions.count == 2 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(controller.qualityOptions.map(\.label), ["180p", "360p"])
        let player = try XCTUnwrap(controller.vlcPlayer)
        let originalTrack = player.currentVideoTrackIndex
        let alternate = try XCTUnwrap(controller.qualityOptions.first { $0.videoTrackIndex != originalTrack })
        controller.selectQuality(alternate.id)
        for _ in 0..<20 {
            if player.currentVideoTrackIndex == alternate.videoTrackIndex { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(player.currentVideoTrackIndex, alternate.videoTrackIndex)
        controller.selectQuality(nil)
        for _ in 0..<20 {
            if player.currentVideoTrackIndex == originalTrack { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(player.currentVideoTrackIndex, originalTrack)
        XCTAssertEqual(controller.qualityLabel, "自动")
    }

}
