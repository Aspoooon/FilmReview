import Foundation
import AVFoundation
import CoreMedia
import CoreGraphics
import AppKit
import UniformTypeIdentifiers

enum VideoInspectionError: LocalizedError {
    case noVideoTrack
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "这个文件里没有找到可播放的视频轨道。"
        case .unreadable(let message):
            return "无法读取视频：\(message)"
        }
    }
}

struct VideoInspector {
    static func isVideoFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let known: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "mpg", "mpeg", "wmv", "webm", "ts", "mts", "m2ts", "dv", "flv"]
        if known.contains(ext) { return true }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .movie) { return true }
        return false
    }

    static func inspect(url: URL) async throws -> VideoInfo {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            throw VideoInspectionError.unreadable(error.localizedDescription)
        }
        guard duration.isValid, duration.seconds.isFinite, duration.seconds > 0 else {
            throw VideoInspectionError.unreadable("视频时长无效，可能是损坏或不完整的文件。")
        }

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = videoTracks.first else { throw VideoInspectionError.noVideoTrack }

        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        let minFrameDuration = try await track.load(.minFrameDuration)
        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []

        let transformed = naturalSize.applying(transform)
        let displayWidth = max(1, Int(abs(transformed.width).rounded()))
        let displayHeight = max(1, Int(abs(transformed.height).rounded()))

        var fps = Double(nominalFrameRate)
        if !fps.isFinite || fps <= 0 {
            if minFrameDuration.isValid, minFrameDuration.seconds > 0 {
                fps = 1.0 / minFrameDuration.seconds
            } else {
                fps = 30
            }
        }

        var frameDuration = minFrameDuration
        if !frameDuration.isValid || frameDuration.seconds <= 0 {
            frameDuration = CMTime(seconds: 1.0 / fps, preferredTimescale: 60000)
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        let durationValue = duration.value
        let durationTimescale = duration.timescale

        return VideoInfo(
            fileName: url.lastPathComponent,
            durationSeconds: duration.seconds,
            durationValue: durationValue,
            durationTimescale: durationTimescale,
            naturalWidth: Int(abs(naturalSize.width).rounded()),
            naturalHeight: Int(abs(naturalSize.height).rounded()),
            displayWidth: displayWidth,
            displayHeight: displayHeight,
            frameRate: fps,
            frameDurationValue: frameDuration.value,
            frameDurationTimescale: frameDuration.timescale,
            hasAudio: !audioTracks.isEmpty,
            fileSize: Int64(fileSize)
        )
    }

    static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolveBookmark(_ data: Data) -> URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: data,
                        options: [],
                        relativeTo: nil,
                        bookmarkDataIsStale: &stale)
    }
}
