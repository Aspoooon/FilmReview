import Foundation
import AVFoundation
import Combine
import CoreMedia
import AppKit

@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentSeconds: Double = 0
    @Published private(set) var isSeeking = false
    @Published private(set) var videoInfo: VideoInfo?
    @Published private(set) var videoURL: URL?
    @Published var volume: Float = 0.9 {
        didSet { player.volume = isMuted ? 0 : volume }
    }
    @Published var isMuted = false {
        didSet { player.isMuted = isMuted }
    }

    let player = AVPlayer()

    private var seekGeneration = 0
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var endObserver: NSObjectProtocol?

    init() {
        player.actionAtItemEnd = .pause
        player.volume = volume
        player.allowsExternalPlayback = false

        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                guard !self.isSeeking, self.player.currentItem != nil else { return }
                let seconds = time.seconds.isFinite ? max(0, time.seconds) : 0
                if abs(seconds - self.currentSeconds) > 0.0001 {
                    self.currentSeconds = seconds
                }
                self.isPlaying = self.player.rate != 0
            }
        }

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.isPlaying = (status == .playing)
            }
            .store(in: &cancellables)

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = false
                if let duration = self.videoInfo?.durationSeconds {
                    self.currentSeconds = max(0, duration - 1.0 / max(self.fps, 1))
                }
            }
        }
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    var fps: Double {
        videoInfo?.frameRate ?? 30
    }

    var duration: Double {
        videoInfo?.durationSeconds ?? 0
    }

    var currentTimecode: String {
        Timecode.string(seconds: currentSeconds, fps: fps)
    }

    var durationTimecode: String {
        Timecode.string(seconds: duration, fps: fps)
    }

    // MARK: - Loading

    func attach(url: URL, info: VideoInfo) {
        if videoURL != url || player.currentItem == nil {
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 0.5
            player.replaceCurrentItem(with: item)
        }
        videoURL = url
        videoInfo = info
        currentSeconds = 0
        isPlaying = false
        player.volume = isMuted ? 0 : volume
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func detach() {
        seekGeneration += 1
        isSeeking = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        videoURL = nil
        videoInfo = nil
        currentSeconds = 0
        isPlaying = false
    }

    // MARK: - Transport

    func togglePlayback() {
        guard player.currentItem != nil else { return }
        if isPlaying {
            pause()
        } else {
            if currentSeconds >= duration - 0.0001 {
                seek(toSeconds: 0, exact: true)
            }
            player.play()
            player.rate = 1
            isPlaying = true
        }
    }

    func play() {
        guard player.currentItem != nil else { return }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
        syncCurrentTime()
    }

    func seek(toSeconds seconds: Double, exact: Bool = true, resume: Bool = false) {
        guard player.currentItem != nil else { return }
        let clamped = min(max(seconds, 0), max(duration, 0))
        let target = CMTime(seconds: clamped, preferredTimescale: 60000)
        currentSeconds = clamped
        let wasPlaying = isPlaying
        seekGeneration += 1
        let generation = seekGeneration
        isSeeking = true
        player.seek(to: target, toleranceBefore: exact ? .zero : CMTime(value: 1, timescale: 30),
                    toleranceAfter: exact ? .zero : CMTime(value: 1, timescale: 30)) { [weak self] completed in
            Task { @MainActor in
                guard let self, self.seekGeneration == generation else { return }
                self.isSeeking = false
                if completed { self.syncCurrentTime() }
                if completed && resume && wasPlaying { self.play() }
            }
        }
    }

    func pinReviewTime() -> CMTime {
        pause()
        if isSeeking {
            return CMTime(seconds: currentSeconds, preferredTimescale: 60000)
        }
        let time = player.currentTime()
        return time.isNumeric ? time : .zero
    }

    func seek(to time: CMTime) {
        seek(toSeconds: time.seconds, exact: true)
    }

    func step(byFrames count: Int) {
        guard let item = player.currentItem else { return }
        player.pause()
        isPlaying = false
        if isAtStart && count < 0 { return }
        if currentSeconds >= duration - 0.0001 && count > 0 { return }
        item.step(byCount: count)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) { [weak self] in
            self?.syncCurrentTime()
        }
    }

    private var isAtStart: Bool { currentSeconds <= 0.00001 }

    func syncCurrentTime() {
        guard player.currentItem != nil, !isSeeking else { return }
        let seconds = player.currentTime().seconds
        if seconds.isFinite {
            currentSeconds = max(0, seconds)
        }
        isPlaying = player.rate != 0
    }

    func toggleMute() {
        isMuted.toggle()
    }
}
