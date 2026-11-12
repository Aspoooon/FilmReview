import Foundation
import AVFoundation
import AppKit
import CoreMedia
import ImageIO
import UniformTypeIdentifiers

struct CapturedFrame {
    let jpegData: Data
    let image: NSImage
    let actualTime: CMTime
    let pixelWidth: Int
    let pixelHeight: Int
}

enum FrameExportError: LocalizedError {
    case captureFailed(String)
    case encodingFailed
    case missingVideo

    var errorDescription: String? {
        switch self {
        case .captureFailed(let message): return "无法从视频画面生成截图：\(message)"
        case .encodingFailed: return "无法编码截图。"
        case .missingVideo: return "源视频文件不存在，请重新关联视频。"
        }
    }
}

enum FrameExporter {

    /// Decodes a full-resolution frame directly from the source video (not a
    /// screenshot of the app window). Uses zero tolerance for a true
    /// frame-accurate capture, with a one-frame tolerance fallback for codecs
    /// that cannot seek with zero tolerance.
    static func capture(videoURL: URL, at requestedTime: CMTime, maxDimension: CGFloat = 2800) async throws -> CapturedFrame {
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw FrameExportError.missingVideo
        }
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)

        var cgImage: CGImage?
        var actualTime: CMTime = requestedTime
        do {
            let result = try await generator.image(at: requestedTime)
            cgImage = result.image
            actualTime = result.actualTime
        } catch {
            // Tolerant retry, still limited to roughly half a frame.
            let info = try? await VideoInspector.inspect(url: videoURL)
            let frameDuration = info?.frameDuration ?? CMTime(value: 1, timescale: 30)
            generator.requestedTimeToleranceBefore = frameDuration
            generator.requestedTimeToleranceAfter = frameDuration
            guard let result = try? await generator.image(at: requestedTime) else {
                throw FrameExportError.captureFailed(error.localizedDescription)
            }
            cgImage = result.image
            actualTime = result.actualTime
        }
        guard let cgImage else { throw FrameExportError.captureFailed("空的画面数据") }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = NSSize(width: cgImage.width, height: cgImage.height)
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92, .progressive: false]) else {
            throw FrameExportError.encodingFailed
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return CapturedFrame(jpegData: jpeg,
                             image: image,
                             actualTime: actualTime,
                             pixelWidth: cgImage.width,
                             pixelHeight: cgImage.height)
    }

    static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func nsImage(from data: Data) -> NSImage? {
        guard let cg = cgImage(from: data) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func thumbnail(from data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
