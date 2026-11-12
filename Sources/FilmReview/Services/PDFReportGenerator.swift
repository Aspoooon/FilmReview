import AppKit
import CoreGraphics
import CoreText

enum PDFReportGenerator {
    private static let pageSize = CGSize(width: 595.28, height: 841.89)
    private static let margin: CGFloat = 34
    private static let bodyTop = pageSize.height - 96
    private static let bodyBottom: CGFloat = 47
    private static let imageWidth: CGFloat = 224
    private static let imageMaxHeight: CGFloat = 128
    private static let textX = margin + imageWidth + 18
    private static let textWidth = pageSize.width - margin - textX
    private static let contentWidth = pageSize.width - 2 * margin
    private static let ink = NSColor(srgbRed: 0.11, green: 0.12, blue: 0.13, alpha: 1)
    private static let secondary = NSColor(srgbRed: 0.33, green: 0.35, blue: 0.38, alpha: 1)
    private static let accent = NSColor(srgbRed: 0.73, green: 0.17, blue: 0.16, alpha: 1)
    private static let ruleColor = NSColor(srgbRed: 0.84, green: 0.85, blue: 0.87, alpha: 1)

    private struct Row {
        let comment: ReviewComment
        let framesetter: CTFramesetter
        let textRange: CFRange
        let textHeight: CGFloat
        let imageSize: CGSize
        let height: CGFloat

        var isContinuation: Bool { textRange.location > 0 }
    }

    static func generate(project: ReviewProject, title: String? = nil) throws -> Data {
        let title = title ?? project.name
        let rows = try paginate(project.sortedComments)
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        let metadata = [kCGPDFContextTitle as String: "\(title) · \(project.name)",
                        kCGPDFContextCreator as String: "FilmReview"]
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox,
                                      metadata as CFDictionary) else {
            throw exportError("无法创建 PDF。")
        }

        for (index, page) in rows.enumerated() {
            context.beginPDFPage(nil)
            drawHeader(title: title, project: project, context: context)
            var y = bodyTop
            for row in page {
                draw(row, top: y, fps: project.videoInfo.frameRate, context: context)
                y -= row.height
            }
            drawRule(y: bodyBottom - 8, context: context)
            drawLine("FilmReview", font: FontBook.medium(size: 9), color: secondary,
                     x: margin, baseline: 25, context: context)
            drawLine("\(index + 1) / \(rows.count)", font: FontBook.monospaced(size: 10),
                     color: secondary, x: pageSize.width - margin - 42,
                     baseline: 25, width: 42, context: context)
            context.endPDFPage()
        }

        context.closePDF()
        return data as Data
    }

    private static func paginate(_ comments: [ReviewComment]) throws -> [[Row]] {
        guard !comments.isEmpty else { throw exportError("添加修改意见后即可导出。") }
        let pageCapacity = bodyTop - bodyBottom
        let rowPadding: CGFloat = 38
        var pages: [[Row]] = [[]]
        var available = pageCapacity

        for comment in comments {
            let text = comment.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = text.isEmpty ? (comment.annotations.isEmpty ? "未填写文字意见" : "画面标注") : text
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3
            paragraph.lineBreakMode = .byWordWrapping
            let attributed = NSAttributedString(string: note, attributes: [
                .font: FontBook.regular(size: 13.5),
                .foregroundColor: text.isEmpty ? secondary : ink,
                .paragraphStyle: paragraph
            ])
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let shotSize = comment.screenshotSize
            let scale = min(imageWidth / shotSize.width, imageMaxHeight / shotSize.height)
            let firstImageSize = CGSize(width: shotSize.width * scale, height: shotSize.height * scale)
            var offset = 0

            while offset < attributed.length {
                let imageSize = offset == 0 ? firstImageSize : .zero
                let remaining = CFRange(location: offset, length: attributed.length - offset)
                let width = offset == 0 ? textWidth : contentWidth
                let fullTextHeight = measuredHeight(framesetter, range: remaining, width: width)
                let fullRowHeight = max(imageSize.height, fullTextHeight) + rowPadding
                let minimumRowHeight = max(imageSize.height, min(fullTextHeight, 64)) + rowPadding
                let fitsOnNewPage = fullRowHeight <= pageCapacity

                if fullRowHeight > available && !pages[pages.count - 1].isEmpty,
                   fitsOnNewPage || minimumRowHeight > available {
                    pages.append([])
                    available = pageCapacity
                }

                let textLimit = available - rowPadding
                let measurePath = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: textLimit),
                                         transform: nil)
                let fittingFrame = CTFramesetterCreateFrame(framesetter, remaining, measurePath, nil)
                let fit = CTFrameGetVisibleStringRange(fittingFrame)
                guard fit.length > 0 else { throw exportError("这条修改意见无法排入页面。") }
                let textHeight = min(textLimit, measuredHeight(framesetter, range: fit, width: width))
                let height = max(imageSize.height, textHeight) + rowPadding
                pages[pages.count - 1].append(Row(comment: comment, framesetter: framesetter,
                                                 textRange: fit, textHeight: textHeight,
                                                 imageSize: imageSize, height: height))
                available -= height
                offset += fit.length
            }
        }

        return pages
    }

    private static func measuredHeight(_ framesetter: CTFramesetter, range: CFRange,
                                       width: CGFloat) -> CGFloat {
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, range, nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil
        )
        return ceil(size.height) + 4
    }

    private static func drawHeader(title: String, project: ReviewProject, context: CGContext) {
        drawLine(title, font: FontBook.semibold(size: 23), color: ink,
                 x: margin, baseline: pageSize.height - 47, width: 404, context: context)
        drawLine("修改意见", font: FontBook.semibold(size: 11), color: accent,
                 x: pageSize.width - margin - 46, baseline: pageSize.height - 46, context: context)
        drawLine("\(project.videoInfo.fileName)  ·  \(project.comments.count) 条",
                 font: FontBook.regular(size: 10.5), color: secondary,
                 x: margin, baseline: pageSize.height - 69, width: pageSize.width - 2 * margin,
                 context: context)
        drawRule(y: pageSize.height - 81, context: context)
    }

    private static func draw(_ row: Row, top: CGFloat, fps: Double, context: CGContext) {
        let label = String(format: "%02d", row.comment.number)
        let timecode = row.comment.timecode(fps: fps)
        let continuation = row.isContinuation ? "  续" : ""
        drawLine("\(label)   \(timecode)\(continuation)", font: FontBook.monospaced(size: 11, weight: .semibold),
                 color: accent, x: margin, baseline: top - 10, context: context)

        if !row.isContinuation {
            let rect = CGRect(x: margin + (imageWidth - row.imageSize.width) / 2,
                              y: top - 22 - row.imageSize.height,
                              width: row.imageSize.width, height: row.imageSize.height)
            if let image = FrameExporter.cgImage(from: row.comment.screenshotJPEG) {
                context.interpolationQuality = .high
                context.draw(image, in: rect)
                AnnotationRenderer.draw(annotations: row.comment.annotations, in: rect,
                                        context: context, lineWidthScale: 1.3)
            } else {
                context.setFillColor(ruleColor.cgColor)
                context.fill(rect)
                drawLine("截图缓存不可用", font: FontBook.regular(size: 10), color: secondary,
                         x: rect.minX + 6, baseline: rect.midY, width: max(1, rect.width - 12), context: context)
            }
        }

        let textRect = CGRect(x: row.isContinuation ? margin : textX,
                              y: top - 22 - row.textHeight,
                              width: row.isContinuation ? contentWidth : textWidth, height: row.textHeight)
        let frame = CTFramesetterCreateFrame(row.framesetter, row.textRange, CGPath(rect: textRect, transform: nil), nil)
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        drawRule(y: top - row.height + 7, context: context)
    }

    private static func drawRule(y: CGFloat, context: CGContext) {
        context.setStrokeColor(ruleColor.cgColor)
        context.setLineWidth(0.6)
        context.move(to: CGPoint(x: margin, y: y))
        context.addLine(to: CGPoint(x: pageSize.width - margin, y: y))
        context.strokePath()
    }

    private static func drawLine(_ text: String, font: NSFont, color: NSColor, x: CGFloat,
                                 baseline: CGFloat, width: CGFloat? = nil, context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let drawnLine: CTLine
        if let width, CTLineGetTypographicBounds(line, nil, nil, nil) > width {
            let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
            drawnLine = CTLineCreateTruncatedLine(line, width, .end, ellipsis) ?? ellipsis
        } else {
            drawnLine = line
        }
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(drawnLine, context)
    }

    private static func exportError(_ message: String) -> NSError {
        NSError(domain: "FilmReview.PDF", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
