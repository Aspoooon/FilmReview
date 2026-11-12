import Foundation

/// SMPTE-style timecode helpers.
///
/// Frame numbers are derived from the real frame rate reported by the media
/// track. The original CMTime for a mark is always stored alongside the
/// display seconds, so seeking back is exact even for variable frame rate
/// footage.
enum Timecode {

    /// Integer frame rate used for the `FF` field (23.976 -> 24, 29.97 -> 30).
    static func frameRateForDisplay(_ fps: Double) -> Int {
        guard fps.isFinite, fps > 0 else { return 30 }
        return max(1, Int(fps.rounded()))
    }

    static func totalFrames(seconds: Double, fps: Double) -> Int {
        guard seconds.isFinite, fps > 0 else { return 0 }
        return max(0, Int((seconds * fps).rounded()))
    }

    /// `HH:MM:SS:FF`
    static func string(seconds: Double, fps: Double) -> String {
        let rate = frameRateForDisplay(fps)
        let total = totalFrames(seconds: max(0, seconds), fps: fps)
        let frames = total % rate
        let totalSeconds = total / rate
        let s = totalSeconds % 60
        let m = (totalSeconds / 60) % 60
        let h = totalSeconds / 3600
        return String(format: "%02d:%02d:%02d:%02d", h, m, s, frames)
    }

    /// `HH:MM:SS` for durations and metadata.
    static func clockString(seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00:00" }
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }

    /// Parses `HH:MM:SS:FF`, `MM:SS:FF`, `SS:FF`, `HH:MM:SS` or `MM:SS`.
    static func parse(_ input: String, fps: Double) -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":").map(String.init)
        let rate = Double(frameRateForDisplay(fps))
        var values = [Double]()
        for part in parts {
            guard let v = Double(part.replacingOccurrences(of: ",", with: ".")), v >= 0 else { return nil }
            values.append(v)
        }
        switch values.count {
        case 4: // HH MM SS FF
            return values[0] * 3600 + values[1] * 60 + values[2] + values[3] / rate
        case 3: // HH MM SS  or  MM SS FF
            // A third component below 60 with something after may be frames.
            return values[0] * 3600 + values[1] * 60 + values[2]
        case 2: // MM SS
            return values[0] * 60 + values[1]
        case 1:
            return values[0]
        default:
            return nil
        }
    }

    /// Parses a timecode that may include frames, falling back gracefully.
    static func parseTimecode(_ input: String, fps: Double) -> Double? {
        let parts = input.split(separator: ":").map(String.init)
        if parts.count == 4, let h = Double(parts[0]), let m = Double(parts[1]),
           let s = Double(parts[2]), let f = Double(parts[3]) {
            let rate = Double(frameRateForDisplay(fps))
            return h * 3600 + m * 60 + s + f / rate
        }
        return parse(input, fps: fps)
    }
}
