import Foundation
import AVFoundation
import AppKit
import CoreMedia

@MainActor
final class ThumbnailService: ObservableObject {
    @Published private(set) var revision = 0

    private var generator: AVAssetImageGenerator?
    private var cache: [Int64: NSImage] = [:]
    private var pending = Set<Int64>()
    private var generationToken = 0
    private var videoURL: URL?
    private var queuedTimes: [Double] = []

    func configure(url: URL) {
        guard videoURL != url else { return }
        videoURL = url
        generationToken += 1
        cache.removeAll()
        pending.removeAll()
        revision += 1

        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 360, height: 240)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.16, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.16, preferredTimescale: 600)
        generator = gen
        if !queuedTimes.isEmpty {
            let queued = queuedTimes
            queuedTimes = []
            request(times: queued)
        }
    }

    func reset() {
        generationToken += 1
        generator = nil
        videoURL = nil
        cache.removeAll()
        pending.removeAll()
        queuedTimes.removeAll()
        revision += 1
    }

    func image(for time: Double) -> NSImage? {
        cache[Self.key(time)]
    }

    func request(times: [Double]) {
        guard let generator else {
            queuedTimes = Array(times.prefix(200))
            return
        }
        var needed: [Int64] = []
        for time in times {
            let key = Self.key(time)
            if cache[key] == nil && !pending.contains(key) {
                needed.append(key)
            }
        }
        guard !needed.isEmpty else { return }
        needed.forEach { pending.insert($0) }
        let token = generationToken
        let cmTimes = needed.map { CMTime(value: CMTimeValue($0), timescale: 1000) }

        generator.generateCGImagesAsynchronously(forTimes: cmTimes.map { NSValue(time: $0) }) { [weak self] requestedTime, cgImage, _, result, _ in
            guard let self else { return }
            let key = Int64((requestedTime.seconds * 1000).rounded())
            Task { @MainActor in
                guard self.generationToken == token else { return }
                self.pending.remove(key)
                if result == .succeeded, let cgImage {
                    let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    self.cache[key] = image
                    if self.cache.count > 900 {
                        self.trimCache()
                    }
                    self.revision &+= 1
                }
            }
        }
    }

    private func trimCache() {
        // Keep the cache bounded without dropping everything.
        let sorted = cache.keys.sorted()
        let dropCount = max(0, sorted.count - 700)
        for key in sorted.prefix(dropCount) {
            cache.removeValue(forKey: key)
        }
    }

    nonisolated private static func key(_ time: Double) -> Int64 {
        Int64((max(0, time) * 1000).rounded())
    }
}
