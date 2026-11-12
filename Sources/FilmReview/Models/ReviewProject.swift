import Foundation
import CoreMedia
import CoreGraphics

struct VideoInfo: Codable, Equatable {
    var fileName: String
    var durationSeconds: Double
    var durationValue: Int64
    var durationTimescale: Int32
    var naturalWidth: Int
    var naturalHeight: Int
    var displayWidth: Int
    var displayHeight: Int
    var frameRate: Double
    var frameDurationValue: Int64
    var frameDurationTimescale: Int32
    var hasAudio: Bool
    var fileSize: Int64

    var duration: CMTime {
        CMTime(value: durationValue, timescale: durationTimescale)
    }

    var frameDuration: CMTime {
        CMTime(value: frameDurationValue, timescale: frameDurationTimescale)
    }

    var isPortrait: Bool { displayHeight > displayWidth }
    var aspectRatio: CGFloat {
        guard displayHeight > 0 else { return 16.0 / 9.0 }
        return CGFloat(displayWidth) / CGFloat(displayHeight)
    }

    var aspectLabel: String {
        let ratio = Double(displayWidth) / Double(max(displayHeight, 1))
        if abs(ratio - 16.0 / 9.0) < 0.02 { return "16:9" }
        if abs(ratio - 9.0 / 16.0) < 0.02 { return "9:16" }
        if abs(ratio - 4.0 / 3.0) < 0.02 { return "4:3" }
        if abs(ratio - 1.0) < 0.02 { return "1:1" }
        if abs(ratio - 2.39) < 0.06 { return "2.39:1" }
        return String(format: "%.2f:1", ratio)
    }

    var resolutionLabel: String { "\(displayWidth) × \(displayHeight)" }

    var frameRateLabel: String {
        let rounded = (frameRate * 100).rounded() / 100
        if abs(rounded - rounded.rounded()) < 0.001 {
            return String(format: "%.0f fps", rounded)
        }
        return String(format: "%.2f fps", rounded)
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

struct ReviewComment: Identifiable, Codable, Equatable {
    var id: UUID
    var number: Int
    /// Exact media timestamp for the captured frame.
    var timeValue: Int64
    var timeTimescale: Int32
    var timeSeconds: Double
    var note: String
    var annotations: [AnnotationElement]
    /// JPEG snapshot cached inside the project file so the report and the
    /// annotation editor still work if the source video moves.
    var screenshotJPEG: Data
    var imagePixelWidth: Int
    var imagePixelHeight: Int
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         number: Int,
         time: CMTime,
         timeSeconds: Double,
         note: String,
         annotations: [AnnotationElement],
         screenshotJPEG: Data,
         imagePixelWidth: Int,
         imagePixelHeight: Int,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.number = number
        self.timeValue = time.value
        self.timeTimescale = time.timescale
        self.timeSeconds = timeSeconds
        self.note = note
        self.annotations = annotations
        self.screenshotJPEG = screenshotJPEG
        self.imagePixelWidth = imagePixelWidth
        self.imagePixelHeight = imagePixelHeight
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var time: CMTime { CMTime(value: timeValue, timescale: timeTimescale) }

    var screenshotSize: CGSize {
        CGSize(width: max(1, imagePixelWidth), height: max(1, imagePixelHeight))
    }

    var timecode: String {
        // The project stores the file's frame rate at project level; this is a
        // last-resort fallback and is normally overridden by the view/PDF.
        Timecode.string(seconds: timeSeconds, fps: 30)
    }

    func timecode(fps: Double) -> String {
        Timecode.string(seconds: timeSeconds, fps: fps)
    }
}

struct ReviewProject: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = ReviewProject.currentVersion
    var name: String
    var videoPath: String
    var videoBookmark: Data?
    var videoInfo: VideoInfo
    var comments: [ReviewComment]
    var createdAt: Date
    var updatedAt: Date
    /// Set once the user has exported; purely informational.
    var lastExportAt: Date?

    init(name: String, videoPath: String, videoBookmark: Data?, videoInfo: VideoInfo) {
        self.name = name
        self.videoPath = videoPath
        self.videoBookmark = videoBookmark
        self.videoInfo = videoInfo
        self.comments = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var sortedComments: [ReviewComment] {
        comments.sorted { a, b in
            if abs(a.timeSeconds - b.timeSeconds) < 0.0005 {
                return a.createdAt < b.createdAt
            }
            return a.timeSeconds < b.timeSeconds
        }
    }

    var videoURL: URL { URL(fileURLWithPath: videoPath) }

    var sourceName: String { videoInfo.fileName }

    mutating func renumber() {
        comments = sortedComments.enumerated().map { index, comment in
            var c = comment
            c.number = index + 1
            return c
        }
    }
}
