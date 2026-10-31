import AVFoundation
import Combine
import MobileVLCKit
import UIKit

@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var vlcPlayer: VLCMediaPlayer?
    let vlcDrawable = UIView()
    @Published private(set) var isPaused = false
    @Published private(set) var ready = false
    @Published private(set) var isBuffering = true
    @Published private(set) var bufferedAhead = 0.0
    @Published private(set) var bufferedRanges: [ClosedRange<Double>] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var qualityOptions: [PlaybackQualityOption] = []
    @Published private(set) var selectedQualityID: String?
    @Published private(set) var detectingQuality = false
    private var qualityTask: Task<Void, Never>?
    private var defaultVLCVideoTrack: Int32?

    var qualityLabel: String {
        qualityOptions.first(where: { $0.id == selectedQualityID })?.menuLabel ?? "自动"
    }

    func selectQuality(_ id: String?) {
        let option = qualityOptions.first { $0.id == id }
        guard id == nil || option != nil else { return }
        if let playback = vlcPlayer {
            guard let track = option?.videoTrackIndex ?? defaultVLCVideoTrack else { return }
            playback.currentVideoTrackIndex = track
        } else if let item = player?.currentItem {
            item.preferredPeakBitRate = option.map { $0.peakBitRate.isFinite ? max(0, $0.peakBitRate) : 0 } ?? 0
            item.preferredMaximumResolution = option.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
        } else { return }
        selectedQualityID = id
    }

    private func discoverAVQuality(asset: AVURLAsset, run: UUID) {
        detectingQuality = true
        qualityTask = Task { [weak self] in
            let variants = try? await asset.load(.variants)
            guard let self, self.generation == run, !Task.isCancelled else { return }
            self.qualityOptions = PlaybackQualityOption.choices((variants ?? []).compactMap { variant -> PlaybackQualityOption? in
                guard let size = variant.videoAttributes?.presentationSize,
                      size.width.isFinite, size.height.isFinite,
                      size.width > 0, size.height > 0, size.width < 100_000, size.height < 100_000 else { return nil }
                let peak = variant.peakBitRate ?? 0
                let rate = peak > 0 ? peak : max(0, variant.averageBitRate ?? 0)
                return PlaybackQualityOption(width: Int(size.width), height: Int(size.height), peakBitRate: rate)
            })
            self.detectingQuality = false
        }
    }

    private func discoverVLCQuality(_ playback: VLCMediaPlayer) {
        if defaultVLCVideoTrack == nil, playback.currentVideoTrackIndex >= 0 {
            defaultVLCVideoTrack = playback.currentVideoTrackIndex
        }
        let indexes = Set((playback.videoTrackIndexes as? [NSNumber] ?? []).map(\.int32Value))
        let tracks = playback.media?.tracksInformation as? [[String: Any]] ?? []
        let options = PlaybackQualityOption.choices(tracks.compactMap { track -> PlaybackQualityOption? in
            guard track[VLCMediaTracksInformationType] as? String == VLCMediaTracksInformationTypeVideo,
                  let id = track[VLCMediaTracksInformationId] as? NSNumber, indexes.contains(id.int32Value), id.int32Value >= 0,
                  let width = track[VLCMediaTracksInformationVideoWidth] as? NSNumber,
                  let height = track[VLCMediaTracksInformationVideoHeight] as? NSNumber else { return nil }
            return PlaybackQualityOption(width: width.intValue, height: height.intValue,
                peakBitRate: (track[VLCMediaTracksInformationBitrate] as? NSNumber)?.doubleValue ?? 0, videoTrackIndex: id.int32Value)
        })
        if options != qualityOptions { qualityOptions = options }
    }

    private var generation = UUID()
    private var progress: ((Double, Double) -> Void)?
    private var ended: (() -> Void)?
    private var reportedEnd = false
    private var seeking = false
    private var seekGeneration = UUID()
    private var lastPosition = 0.0
    private var lastDuration = 0.0
    private var asset: AVURLAsset?
    private var awakeOwner: UUID?
    private var foreground = true
    private(set) var playbackRate: Float = 1

    func setRate(_ value: Double) {
        guard value.isFinite, (0.5...2).contains(value) else { return }
        playbackRate = Float(value)
        player?.defaultRate = playbackRate
        if let player, player.rate != 0 { player.rate = playbackRate }
        vlcPlayer?.rate = playbackRate
    }
    private var vlcStateObserver: NSObjectProtocol?

    func start(resource: PlaybackResource, position: Double, buffer: Double, volume: Double = 1,
               onProgress: ((Double, Double) -> Void)?, onEnded: (() -> Void)?, engine: PlaybackEngine = .avPlayer) async {
        if engine == .vlc {
            await startVLC(resource: resource, position: position, buffer: buffer, volume: volume, onProgress: onProgress, onEnded: onEnded)
            return
        }
        stop()
        let run = generation
        progress = onProgress; ended = onEnded
        ready = false; isBuffering = true; bufferedAhead = 0; errorMessage = nil
        reportedEnd = false; lastPosition = position; lastDuration = 0
        let asset = AVURLAsset(url: resource.url, options: ["AVURLAssetHTTPHeaderFieldsKey": resource.headers])
        self.asset = asset
        let item = AVPlayerItem(asset: asset)
        // Let startup and progress restoration finish before requesting a larger forward buffer.
        item.preferredForwardBufferDuration = 0
        let playback = AVPlayer(playerItem: item)
        playback.defaultRate = playbackRate
        playback.automaticallyWaitsToMinimizeStalling = true
        playback.volume = Float(min(1, max(0, volume)))
        player = playback
        updateAwake(true)
        playback.play()
        let deadline = ContinuousClock.now.advanced(by: .seconds(45))
        while item.status == .unknown {
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard generation == run, !Task.isCancelled else { return }
            if ContinuousClock.now >= deadline {
                fail("媒体连接等待超过 45 秒，请重试或切换线路。", player: playback)
                return
            }
        }
        guard generation == run, !Task.isCancelled else { return }
        guard item.status == .readyToPlay else {
            fail(message(for: item.error, fallback: "媒体加载失败"), player: playback)
            return
        }
        if position.isFinite && position > 0 {
            playback.pause()
            let length = item.duration.seconds
            let target = length.isFinite && length > 0 && position >= length - 1 ? 0 : position
            let restored = await performSeek(target, player: playback, item: item)
            guard generation == run, !Task.isCancelled else { return }
            guard restored else {
                fail("无法恢复上次进度，请重试或从头播放。", player: playback)
                return
            }
        }
        item.preferredForwardBufferDuration = max(0, buffer)
        ready = true
        discoverAVQuality(asset: asset, run: run)
        playback.play()
        saveProgress()
        var ticks = 0
        while generation == run, !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard generation == run, !Task.isCancelled else { return }
            isPaused = ready && playback.timeControlStatus == .paused && !reportedEnd
            updateAwake(playback.timeControlStatus != .paused)
            isBuffering = playback.timeControlStatus == .waitingToPlayAtSpecifiedRate || seeking
            let current = playback.currentTime().seconds
            bufferedRanges = item.loadedTimeRanges.compactMap { value -> ClosedRange<Double>? in
                let range = value.timeRangeValue
                let start = range.start.seconds, end = CMTimeRangeGetEnd(range).seconds
                guard start.isFinite, end.isFinite, end >= start, start >= 0 else { return nil }
                return start...end
            }
            bufferedAhead = item.loadedTimeRanges.compactMap { value -> Double? in
                let range = value.timeRangeValue
                let start = range.start.seconds, end = CMTimeRangeGetEnd(range).seconds
                guard start.isFinite, end.isFinite, current.isFinite,
                      start <= current + 0.1, end >= current else { return nil }
                return max(0, end - current)
            }.max() ?? 0
            if item.status == .failed {
                saveProgress()
                fail(message(for: item.error, fallback: "播放中断"), player: playback)
                return
            }
            if reportedEnd && playback.timeControlStatus == .playing { reportedEnd = false }
            ticks += 1
            if ticks % 8 == 0 { saveProgress() }
        }
    }

    func stop() {
        saveProgress()
        qualityTask?.cancel(); qualityTask = nil
        qualityOptions = []; selectedQualityID = nil; detectingQuality = false; defaultVLCVideoTrack = nil
        generation = UUID()
        if let vlcStateObserver {
            NotificationCenter.default.removeObserver(vlcStateObserver)
            self.vlcStateObserver = nil
        }
        vlcPlayer?.stop()
        vlcPlayer?.drawable = nil
        vlcPlayer?.media = nil
        vlcPlayer = nil
        player?.pause()
        player?.cancelPendingPrerolls()
        player?.currentItem?.cancelPendingSeeks()
        player?.replaceCurrentItem(with: nil)
        asset?.cancelLoading()
        asset = nil
        player = nil
        ready = false
        isPaused = false
        bufferedRanges = []
        bufferedAhead = 0
        updateAwake(false)
        seeking = false
        progress = nil; ended = nil
    }

    func saveProgress() {
        if let vlcPlayer {
            guard ready, !seeking else { return }
            let seconds = reportedEnd && lastDuration > 0 ? lastDuration : Double(vlcPlayer.time.intValue) / 1000
            guard seconds >= 0 else { return }
            lastPosition = seconds
            let length = Double(vlcPlayer.media?.length.intValue ?? 0) / 1000
            if length > 0 { lastDuration = length }
            progress?(lastPosition, lastDuration)
            return
        }
        guard ready, !seeking, let player, let item = player.currentItem else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds >= 0 else { return }
        lastPosition = seconds
        let duration = item.duration.seconds
        if duration.isFinite, duration > 0 { lastDuration = duration }
        progress?(lastPosition, lastDuration)
    }

    var retryPosition: Double { lastPosition }
    var duration: Double { vlcPlayer.map { Double($0.media?.length.intValue ?? 0) / 1000 } ?? player?.currentItem?.duration.seconds ?? 0 }
    var position: Double { vlcPlayer.map { Double($0.time.intValue) / 1000 } ?? player?.currentTime().seconds ?? 0 }
    var canSeek: Bool { ready && duration.isFinite && duration > 0 && (vlcPlayer?.isSeekable ?? true) }
    var isPlaying: Bool { vlcPlayer?.isPlaying ?? (player?.timeControlStatus == .playing) }
    func togglePlay() {
        guard ready, errorMessage == nil else { return }
        if let vlcPlayer {
            isPaused.toggle()
            isPaused ? vlcPlayer.pause() : vlcPlayer.play()
        } else if let player {
            isPaused = player.timeControlStatus != .paused
            isPaused ? player.pause() : player.play()
        }
        updateAwake(!isPaused)
        saveProgress()
    }
    func setVolume(_ value: Double) {
        player?.volume = Float(value)
        vlcPlayer?.audio?.volume = Int32(value * 100)
    }

    func seek(to seconds: Double) async {
        if let vlcPlayer {
            guard canSeek else { return }
            reportedEnd = false
            let run = generation
            let seekID = UUID()
            seekGeneration = seekID
            let target = PlaybackGestureMath.seekTarget(start: seconds, delta: 0, duration: duration)
            seeking = true
            vlcPlayer.time = VLCTime(int: Int32(target * 1000))
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            while abs(position - target) > 1 {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard run == generation, seekID == seekGeneration else { return }
                if ContinuousClock.now >= deadline { break }
            }
            guard run == generation, seekID == seekGeneration else { return }
            seeking = false
            if abs(position - target) <= 1 { saveProgress() }
            else { errorMessage = "VLC 跳转未完成，请重试。" }
            return
        }
        guard canSeek, let player, let item = player.currentItem else { return }
        let run = generation
        let seekID = UUID()
        seekGeneration = seekID
        let shouldPlay = player.timeControlStatus != .paused
        seeking = true
        reportedEnd = false
        let succeeded = await performSeek(PlaybackGestureMath.seekTarget(start: seconds, delta: 0, duration: duration),
                                          player: player, item: item)
        guard run == generation, seekGeneration == seekID else { return }
        seeking = false
        if succeeded {
            errorMessage = nil
            saveProgress()
            if shouldPlay { player.play() }
        } else { errorMessage = "跳转未完成，请重试。" }
    }

    func setForeground(_ active: Bool) {
        foreground = active
        updateAwake(active && (player != nil || vlcPlayer != nil) && errorMessage == nil && (!ready || isPlaying || isBuffering))
    }

    private func updateAwake(_ needed: Bool) {
        if needed && foreground {
            if awakeOwner == nil { awakeOwner = ScreenAwakeManager.shared.acquire() }
            ScreenAwakeManager.shared.refresh()
        } else if let owner = awakeOwner {
            ScreenAwakeManager.shared.release(owner)
            awakeOwner = nil
        }
    }

    func setBuffer(_ seconds: Double) { player?.currentItem?.preferredForwardBufferDuration = max(0, seconds) }

    func didEnd(_ item: AVPlayerItem) {
        guard item === player?.currentItem, ready, !reportedEnd else { return }
        reportedEnd = true
        updateAwake(false)
        isBuffering = false
        saveProgress()
        ended?()
    }

    private func performSeek(_ seconds: Double, player: AVPlayer, item: AVPlayerItem) async -> Bool {
        let timeout = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            item.cancelPendingSeeks()
        }
        let result = await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                                       toleranceBefore: CMTime(seconds: 1, preferredTimescale: 600),
                                       toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600))
        timeout.cancel()
        return result
    }

    private func fail(_ message: String, player: AVPlayer) {
        errorMessage = message
        updateAwake(false)
        isBuffering = false
        player.pause()
    }

    private func message(for error: Error?, fallback: String) -> String {
        guard let error else { return fallback + "，请重试或切换线路。" }
        let ns = error as NSError
        return "\(error.localizedDescription)\n\(ns.domain) (\(ns.code))"
    }
}

extension PlaybackController {
    private func finishVLC() {
        guard vlcPlayer != nil, !reportedEnd else { return }
        saveProgress()
        if duration > 0 { lastPosition = duration; lastDuration = duration; progress?(duration, duration) }
        reportedEnd = true
        isBuffering = false
        updateAwake(false)
        ended?()
    }

    private func startVLC(resource: PlaybackResource, position: Double, buffer: Double, volume: Double,
                          onProgress: ((Double, Double) -> Void)?, onEnded: (() -> Void)?) async {
        stop()
        let run = generation
        progress = onProgress; ended = onEnded
        ready = false; isBuffering = true; bufferedAhead = 0; errorMessage = nil
        reportedEnd = false; lastPosition = position; lastDuration = 0
        let supportedHeaders = Set(["user-agent", "referer"])
        guard resource.headers.keys.allSatisfy({ supportedHeaders.contains($0.lowercased()) }) else {
            errorMessage = "此线路包含 VLC 3 不支持的自定义请求头，请改用 AVPlayer。"
            isBuffering = false
            return
        }
        let playback = VLCMediaPlayer()
        let media = VLCMedia(url: resource.url)
        media.addOption(":network-caching=\(Int(buffer > 0 ? min(buffer, 3) * 1000 : 1000))")
        media.addOption(":http-reconnect")
        if let ua = resource.headers.first(where: { $0.key.lowercased() == "user-agent" })?.value {
            media.addOption(":http-user-agent=\(ua)")
        }
        if let referrer = resource.headers.first(where: { $0.key.lowercased() == "referer" })?.value {
            media.addOption(":http-referrer=\(referrer)")
        }

        playback.drawable = vlcDrawable
        playback.media = media
        vlcPlayer = playback
        vlcStateObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("VLCMediaPlayerStateChanged"), object: playback, queue: .main
        ) { [weak self, weak playback] _ in
            MainActor.assumeIsolated {
                guard let self, let playback, self.vlcPlayer === playback else { return }
                if playback.state == .ended { self.finishVLC() }
            }
        }
        playback.audio?.volume = Int32(min(1, max(0, volume)) * 100)
        updateAwake(true)
        playback.play()
        let deadline = ContinuousClock.now.advanced(by: .seconds(45))
        var ticks = 0
        var restoreRequested = false
        var restoreDeadline: ContinuousClock.Instant?
        while generation == run, !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard generation == run, !Task.isCancelled else { return }
            isPaused = ready && playback.state == .paused && !reportedEnd
            switch playback.state {
            case .error:
                saveProgress()
                errorMessage = "VLC 无法打开此媒体，请重试或切换线路/内核。"
                playback.stop(); isBuffering = false; updateAwake(false)
                return
            case .ended:
                if ready && !reportedEnd {
                    finishVLC()
                }
                return
            case .playing, .paused:
                if playback.rate != playbackRate { playback.rate = playbackRate }
                isBuffering = false
                if playback.isPlaying { reportedEnd = false }
            case .opening, .buffering:
                isBuffering = true
            default: break
            }
            let mediaTime = Double(playback.time.intValue) / 1000
            // libVLC 3 can retain the buffering state after actual output has started.
            if playback.state == .playing || (playback.isPlaying && mediaTime > 0) {
                let length = Double(media.length.intValue) / 1000
                let target = length > 0 && position >= length - 1 ? 0 : position
                if !ready && target > 1 && mediaTime < target - 1 {
                    if restoreDeadline == nil { restoreDeadline = ContinuousClock.now.advanced(by: .seconds(15)) }
                    if !restoreRequested && playback.isSeekable {
                        playback.time = VLCTime(int: Int32(min(target, Double(Int32.max) / 1000) * 1000))
                        restoreRequested = true
                    }
                    if let restoreDeadline, ContinuousClock.now >= restoreDeadline {
                        errorMessage = "VLC 无法恢复进度，请重试或从头播放。"
                        playback.pause(); isBuffering = false; updateAwake(false)
                        return
                    }
                } else {
                    ready = true
                    isBuffering = false
                }
            }
            if !ready && ContinuousClock.now >= deadline {
                errorMessage = "VLC 连接等待超过 45 秒，请重试或切换线路。"
                playback.stop(); isBuffering = false; updateAwake(false)
                return
            }
            if ready && ticks % 4 == 0 { discoverVLCQuality(playback) }
            updateAwake(!ready || playback.isPlaying || isBuffering)
            ticks += 1
            if ticks % 8 == 0 { saveProgress() }
        }
    }
}
