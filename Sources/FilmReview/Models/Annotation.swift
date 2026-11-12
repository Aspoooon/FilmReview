import Foundation
import AppKit
import CoreGraphics

struct NormalizedPoint: Codable, Equatable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            self.x = 0; self.y = 0; return
        }
        self.x = min(max(Double(point.x / size.width), 0), 1)
        self.y = min(max(Double(point.y / size.height), 0), 1)
    }

    func point(in size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }
}

enum AnnotationKind: String, Codable, CaseIterable, Identifiable {
    case rectangle
    case arrow
    case text
    case freehand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rectangle: return "矩形框"
        case .arrow: return "箭头"
        case .text: return "文字"
        case .freehand: return "自由画笔"
        }
    }

    var symbol: String {
        switch self {
        case .rectangle: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .text: return "character"
        case .freehand: return "scribble"
        }
    }
}

/// A single vector annotation. All coordinates are normalised (0...1) against
/// the video frame, so annotations survive window resizing and are reused at
/// full resolution in PDF exports.
struct AnnotationElement: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: AnnotationKind
    var colorHex: String
    /// Stroke width expressed in reference points at a 1000pt-wide frame.
    var lineWidth: Double
    var points: [NormalizedPoint]
    var text: String?
    /// Font size expressed in reference points at a 1000pt-wide frame.
    var fontSize: Double

    init(kind: AnnotationKind,
         colorHex: String = AnnotationPalette.defaultColor,
         lineWidth: Double = AnnotationPalette.defaultLineWidth,
         points: [NormalizedPoint],
         text: String? = nil,
         fontSize: Double = AnnotationPalette.defaultFontSize) {
        self.id = UUID()
        self.kind = kind
        self.colorHex = colorHex
        self.lineWidth = lineWidth
        self.points = points
        self.text = text
        self.fontSize = fontSize
    }

    // MARK: - Geometry

    var boundingRect: CGRect {
        guard !points.isEmpty else { return .zero }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Hit test in normalised coordinates. `tolerance` is expressed in the
    /// same normalised space (callers scale from view points).
    func hitTest(_ p: NormalizedPoint, tolerance: CGSize) -> Bool {
        switch kind {
        case .rectangle:
            guard points.count >= 2 else { return false }
            let rect = boundingRect.insetBy(dx: -tolerance.width, dy: -tolerance.height)
            return rect.contains(CGPoint(x: p.x, y: p.y))
        case .arrow:
            guard points.count >= 2 else { return false }
            return Self.distanceFromSegment(point: CGPoint(x: p.x, y: p.y),
                                            a: CGPoint(x: points[0].x, y: points[0].y),
                                            b: CGPoint(x: points[1].x, y: points[1].y))
                < max(tolerance.width, tolerance.height)
        case .freehand:
            guard points.count >= 2 else {
                guard let first = points.first else { return false }
                return hypot(first.x - p.x, first.y - p.y) < max(tolerance.width, tolerance.height)
            }
            for i in 0..<(points.count - 1) {
                let d = Self.distanceFromSegment(point: CGPoint(x: p.x, y: p.y),
                                                 a: CGPoint(x: points[i].x, y: points[i].y),
                                                 b: CGPoint(x: points[i + 1].x, y: points[i + 1].y))
                if d < max(tolerance.width, tolerance.height) { return true }
            }
            return false
        case .text:
            guard let first = points.first else { return false }
            let estWidth = Double((text ?? "").count) * fontSize * 0.62 / 1000.0
            let estHeight = fontSize * 1.4 / 1000.0
            let rect = CGRect(x: first.x - 0.01,
                              y: first.y - 0.01,
                              width: max(estWidth, 0.03) + 0.02,
                              height: estHeight + 0.02)
            return rect.insetBy(dx: -tolerance.width, dy: -tolerance.height)
                .contains(CGPoint(x: p.x, y: p.y))
        }
    }

    mutating func offset(by dx: Double, dy: Double) {
        points = points.map { NormalizedPoint(x: min(max($0.x + dx, 0), 1),
                                              y: min(max($0.y + dy, 0), 1)) }
    }

    private static func distanceFromSegment(point p: CGPoint, a: CGPoint, b: CGPoint) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared == 0 { return Double(hypot(p.x - a.x, p.y - a.y)) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared
        t = min(max(t, 0), 1)
        let closest = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return Double(hypot(p.x - closest.x, p.y - closest.y))
    }
}

enum AnnotationPalette {
    static let defaultColor = "#FF3B30"
    static let defaultLineWidth: Double = 4.5
    static let defaultFontSize: Double = 34

    static let colors: [String] = [
        "#FF3B30", // red
        "#FFD60A", // yellow
        "#0A84FF", // blue
        "#30D158", // green
        "#FFFFFF", // white
        "#000000"  // black
    ]

    static func color(for hex: String) -> NSColor {
        NSColor(hex: hex) ?? .systemRed
    }

    static func cgColor(for hex: String) -> CGColor {
        color(for: hex).cgColor
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let int = UInt64(value, radix: 16) else { return nil }
        let r = CGFloat((int & 0xFF0000) >> 16) / 255
        let g = CGFloat((int & 0x00FF00) >> 8) / 255
        let b = CGFloat(int & 0x0000FF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

enum AnnotationTool: String, CaseIterable, Identifiable {
    case select
    case rectangle
    case arrow
    case text
    case freehand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: return "选择"
        case .rectangle: return "矩形框"
        case .arrow: return "箭头"
        case .text: return "文字"
        case .freehand: return "画笔"
        }
    }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .text: return "character"
        case .freehand: return "scribble"
        }
    }

    var annotationKind: AnnotationKind? {
        switch self {
        case .select: return nil
        case .rectangle: return .rectangle
        case .arrow: return .arrow
        case .text: return .text
        case .freehand: return .freehand
        }
    }
}
