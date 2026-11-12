import Foundation
import AppKit
import CoreText
import CoreGraphics
import SwiftUI

enum FontBook {
    static func annotationFont(size: CGFloat) -> NSFont {
        NSFont(name: "PingFangSC-Semibold", size: size)
            ?? NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    static func annotationSwiftUIFont(size: CGFloat) -> Font {
        if NSFont(name: "PingFangSC-Semibold", size: size) != nil {
            return .custom("PingFang SC", size: size).weight(.semibold)
        }
        return .system(size: size, weight: .semibold)
    }

    static func regular(size: CGFloat) -> NSFont {
        NSFont(name: "PingFangSC-Regular", size: size)
            ?? NSFont.systemFont(ofSize: size)
    }

    static func medium(size: CGFloat) -> NSFont {
        NSFont(name: "PingFangSC-Medium", size: size)
            ?? NSFont.systemFont(ofSize: size, weight: .medium)
    }

    static func semibold(size: CGFloat) -> NSFont {
        NSFont(name: "PingFangSC-Semibold", size: size)
            ?? NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    static func monospaced(size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }
}

/// Shared vector renderer used for PDF pages and composited preview images.
/// Coordinates are normalised with (0,0) at the top-left of the video frame;
/// Core Graphics output flips them to its bottom-left origin.
enum AnnotationRenderer {

    static func draw(annotations: [AnnotationElement],
                     in rect: CGRect,
                     context: CGContext,
                     lineWidthScale: CGFloat = 1.0) {
        guard rect.width > 0, rect.height > 0 else { return }
        let scale = rect.width / 1000.0
        for element in annotations {
            draw(element: element, in: rect, context: context, scale: scale * lineWidthScale)
        }
    }

    static func draw(element: AnnotationElement,
                     in rect: CGRect,
                     context: CGContext,
                     scale: CGFloat) {
        guard !element.points.isEmpty else { return }
        let color = NSColor(hex: element.colorHex) ?? .systemRed
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(max(0.8, element.lineWidth * scale))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        func convert(_ p: NormalizedPoint) -> CGPoint {
            CGPoint(x: rect.minX + p.x * rect.width,
                    y: rect.maxY - p.y * rect.height)
        }

        switch element.kind {
        case .rectangle:
            guard element.points.count >= 2 else { break }
            let a = convert(element.points[0])
            let b = convert(element.points[1])
            let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                           width: abs(b.x - a.x), height: abs(b.y - a.y))
            context.stroke(r)

        case .arrow:
            guard element.points.count >= 2 else { break }
            let a = convert(element.points[0])
            let b = convert(element.points[1])
            let lineWidth = max(0.8, element.lineWidth * scale)
            drawArrow(context: context, from: a, to: b, lineWidth: lineWidth)

        case .freehand:
            guard let first = element.points.first else { break }
            let path = CGMutablePath()
            path.move(to: convert(first))
            for p in element.points.dropFirst() {
                path.addLine(to: convert(p))
            }
            context.addPath(path)
            context.strokePath()

        case .text:
            guard let first = element.points.first, let text = element.text, !text.isEmpty else { break }
            let size = max(6, element.fontSize * scale)
            let font = FontBook.annotationFont(size: size)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let line = CTLineCreateWithAttributedString(attributed)
            let top = convert(first)
            let ascent = CTFontGetAscent(font as CTFont)
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: top.x, y: top.y - ascent)
            CTLineDraw(line, context)
        }
        context.restoreGState()
    }

    private static func drawArrow(context: CGContext, from a: CGPoint, to b: CGPoint, lineWidth: CGFloat) {
        context.setLineWidth(lineWidth)
        context.beginPath()
        context.move(to: a)
        context.addLine(to: b)
        context.strokePath()

        let angle = atan2(b.y - a.y, b.x - a.x)
        let headLength = max(10, lineWidth * 4.2)
        let headAngle: CGFloat = .pi / 7
        let p1 = CGPoint(x: b.x - headLength * cos(angle - headAngle),
                         y: b.y - headLength * sin(angle - headAngle))
        let p2 = CGPoint(x: b.x - headLength * cos(angle + headAngle),
                         y: b.y - headLength * sin(angle + headAngle))
        context.beginPath()
        context.move(to: b)
        context.addLine(to: p1)
        context.addLine(to: p2)
        context.closePath()
        context.fillPath()
    }

    /// Composites a stored snapshot and its vector annotations into a bitmap at
    /// (or capped below) the snapshot's native resolution.
    static func composite(screenshotJPEG: Data,
                          annotations: [AnnotationElement],
                          maxPixelSize: CGFloat? = nil) -> NSImage? {
        guard let cg = FrameExporter.cgImage(from: screenshotJPEG) else { return nil }
        let pixelWidth = CGFloat(cg.width)
        let pixelHeight = CGFloat(cg.height)
        var outputWidth = pixelWidth
        var outputHeight = pixelHeight
        if let maxPixelSize, max(pixelWidth, pixelHeight) > maxPixelSize {
            let factor = maxPixelSize / max(pixelWidth, pixelHeight)
            outputWidth = (pixelWidth * factor).rounded()
            outputHeight = (pixelHeight * factor).rounded()
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil,
                                  width: Int(outputWidth),
                                  height: Int(outputHeight),
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        let rect = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(rect)
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: rect)
        draw(annotations: annotations, in: rect, context: ctx)
        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: outputWidth, height: outputHeight))
    }
}

extension GraphicsContext {
    /// Draws the annotation set inside `rect` using SwiftUI's top-left origin.
    mutating func drawAnnotations(_ annotations: [AnnotationElement],
                                  in rect: CGRect,
                                  selectedID: UUID? = nil) {
        guard rect.width > 0, rect.height > 0 else { return }
        let scale = rect.width / 1000.0
        for element in annotations {
            let color = Color(nsColor: NSColor(hex: element.colorHex) ?? .systemRed)
            let lineWidth = max(0.8, element.lineWidth * scale)
            let points = element.points.map {
                CGPoint(x: rect.minX + $0.x * rect.width,
                        y: rect.minY + $0.y * rect.height)
            }

            switch element.kind {
            case .rectangle:
                guard points.count >= 2 else { continue }
                let r = CGRect(x: min(points[0].x, points[1].x),
                               y: min(points[0].y, points[1].y),
                               width: abs(points[1].x - points[0].x),
                               height: abs(points[1].y - points[0].y))
                stroke(Path(r), with: .color(color), lineWidth: lineWidth)
                fill(Path(r), with: .color(color.opacity(0.06)))

            case .arrow:
                guard points.count >= 2 else { continue }
                let a = points[0], b = points[1]
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                stroke(path, with: .color(color), lineWidth: lineWidth)
                let angle = atan2(b.y - a.y, b.x - a.x)
                let headLength = max(10, lineWidth * 4.2)
                let headAngle: CGFloat = .pi / 7
                let p1 = CGPoint(x: b.x - headLength * cos(angle - headAngle),
                                 y: b.y - headLength * sin(angle - headAngle))
                let p2 = CGPoint(x: b.x - headLength * cos(angle + headAngle),
                                 y: b.y - headLength * sin(angle + headAngle))
                var head = Path()
                head.move(to: b)
                head.addLine(to: p1)
                head.addLine(to: p2)
                head.closeSubpath()
                fill(head, with: .color(color))

            case .freehand:
                guard let first = points.first else { continue }
                var path = Path()
                path.move(to: first)
                for p in points.dropFirst() { path.addLine(to: p) }
                stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

            case .text:
                guard let first = points.first, let text = element.text, !text.isEmpty else { continue }
                let size = max(7, element.fontSize * scale)
                let resolved = Text(text)
                    .font(FontBook.annotationSwiftUIFont(size: size))
                    .foregroundColor(color)
                draw(resolved, at: first, anchor: .topLeading)
            }

            if element.id == selectedID {
                drawSelection(for: element, in: rect, scale: scale)
            }
        }
    }

    private mutating func drawSelection(for element: AnnotationElement,
                                        in rect: CGRect,
                                        scale: CGFloat) {
        let accent = Color.white.opacity(0.9)
        var box: CGRect = .zero
        if element.kind == .text, let p = element.points.first {
            let size = max(7, element.fontSize * scale)
            let width = max(40, CGFloat((element.text ?? "").count) * size * 0.9)
            box = CGRect(x: rect.minX + p.x * rect.width - 4,
                         y: rect.minY + p.y * rect.height - 4,
                         width: width + 8,
                         height: size * 1.5 + 8)
        } else {
            let b = element.boundingRect
            box = CGRect(x: rect.minX + b.minX * rect.width,
                         y: rect.minY + b.minY * rect.height,
                         width: b.width * rect.width,
                         height: b.height * rect.height)
            box = box.insetBy(dx: -5, dy: -5)
        }
        stroke(Path(box), with: .color(accent),
               style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
        if element.kind != .text && !element.points.isEmpty {
            for p in element.points {
                let cp = CGPoint(x: rect.minX + p.x * rect.width,
                                 y: rect.minY + p.y * rect.height)
                fill(Path(ellipseIn: CGRect(x: cp.x - 3, y: cp.y - 3, width: 6, height: 6)),
                     with: .color(accent))
            }
        }
    }
}
