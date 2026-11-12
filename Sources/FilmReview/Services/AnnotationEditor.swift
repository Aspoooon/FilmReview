import Foundation
import AppKit
import CoreMedia
import SwiftUI

@MainActor
final class AnnotationEditor: ObservableObject {
    enum Mode {
        case add
        case edit
    }

    let mode: Mode
    let commentID: UUID?
    let imageData: Data
    let image: NSImage
    let time: CMTime
    let timeSeconds: Double
    let initialAnnotations: [AnnotationElement]
    let initialNote: String

    @Published var annotations: [AnnotationElement]
    @Published var selectedID: UUID?
    @Published var tool: AnnotationTool = .rectangle
    @Published var colorHex: String = AnnotationPalette.defaultColor
    @Published var lineWidth: Double = AnnotationPalette.defaultLineWidth
    @Published var fontSize: Double = AnnotationPalette.defaultFontSize
    @Published var note: String
    @Published var textEditingID: UUID?

    private var undoStack: [[AnnotationElement]] = []
    private var redoStack: [[AnnotationElement]] = []
    private var dragStart: NormalizedPoint?
    private var dragOriginElement: AnnotationElement?
    private var dragElementID: UUID?
    private var hasPushedForDrag = false
    private var textUndoPushed = false

    init(mode: Mode,
         commentID: UUID?,
         imageData: Data,
         image: NSImage,
         time: CMTime,
         timeSeconds: Double,
         note: String,
         annotations: [AnnotationElement]) {
        self.mode = mode
        self.commentID = commentID
        self.imageData = imageData
        self.image = image
        self.time = time
        self.timeSeconds = timeSeconds
        self.note = note
        self.annotations = annotations
        self.initialAnnotations = annotations
        self.initialNote = note
        let portrait = image.size.height > image.size.width
        self.lineWidth = portrait ? 7.0 : AnnotationPalette.defaultLineWidth
        self.fontSize = portrait ? 58.0 : AnnotationPalette.defaultFontSize
    }

    var hasChanges: Bool {
        annotations != initialAnnotations || note != initialNote
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var selectedElement: AnnotationElement? {
        guard let selectedID else { return nil }
        return annotations.first(where: { $0.id == selectedID })
    }

    var isEditingText: Bool { textEditingID != nil }

    // MARK: - Tools

    func chooseTool(_ newTool: AnnotationTool) {
        tool = newTool
        textEditingID = nil
        if newTool != .select {
            selectedID = nil
        }
    }

    func selectElement(_ id: UUID?) {
        selectedID = id
        textUndoPushed = false
        if let id, let element = annotations.first(where: { $0.id == id }) {
            colorHex = element.colorHex
            lineWidth = element.lineWidth
            fontSize = element.fontSize
        }
        if let id, let element = annotations.first(where: { $0.id == id }), element.kind == .text {
            textEditingID = id
        } else {
            textEditingID = nil
        }
    }

    func applyColor(_ hex: String) {
        colorHex = hex
        guard let id = selectedID, let index = index(of: id) else { return }
        pushUndo()
        annotations[index].colorHex = hex
    }

    func beginStyleEdit() {
        guard selectedID != nil else { return }
        pushUndo()
    }

    func applyLineWidth(_ width: Double) {
        lineWidth = width
        guard let id = selectedID, let index = index(of: id) else { return }
        annotations[index].lineWidth = width
    }

    func applyFontSize(_ size: Double) {
        fontSize = size
        guard let id = selectedID, let index = index(of: id) else { return }
        annotations[index].fontSize = size
    }

    func updateSelectedText(_ newText: String) {
        guard let id = selectedID, let index = index(of: id) else { return }
        if !textUndoPushed {
            pushUndo()
            textUndoPushed = true
        }
        annotations[index].text = newText
    }

    // MARK: - Canvas interaction

    func canvasDragBegan(at point: NormalizedPoint, canvasSize: CGSize) {
        textEditingID = nil
        let tolerance = CGSize(width: max(0.001, 10 / max(canvasSize.width, 1)),
                               height: max(0.001, 10 / max(canvasSize.height, 1)))
        if tool == .select {
            let hit = annotations.reversed().first { $0.hitTest(point, tolerance: tolerance) }
            if let hit {
                selectedID = hit.id
                textUndoPushed = false
                dragElementID = hit.id
                dragOriginElement = hit
                dragStart = point
                hasPushedForDrag = false
                tool = .select
                if hit.kind == .text {
                    textEditingID = hit.id
                }
            } else {
                selectedID = nil
                textEditingID = nil
            }
            return
        }

        guard let kind = tool.annotationKind else { return }
        pushUndo()
        hasPushedForDrag = true
        var element = AnnotationElement(kind: kind,
                                        colorHex: colorHex,
                                        lineWidth: lineWidth,
                                        points: [point],
                                        text: kind == .text ? "文字" : nil,
                                        fontSize: fontSize)
        if kind != .text {
            element.points.append(point)
        }
        annotations.append(element)
        selectedID = element.id
        dragElementID = element.id
        dragStart = point
        dragOriginElement = nil
        if kind == .text {
            textEditingID = element.id
            // Creation already pushed an undo snapshot; typing the caption
            // belongs to the same undo step.
            textUndoPushed = true
            tool = .select
        }
    }

    func canvasDragChanged(to point: NormalizedPoint) {
        guard let id = dragElementID, let index = index(of: id) else { return }
        guard let start = dragStart else { return }
        if annotations[index].kind == .text {
            return
        }
        if tool == .select || dragOriginElement != nil {
            guard let origin = dragOriginElement else { return }
            let dx = point.x - start.x
            let dy = point.y - start.y
            if !hasPushedForDrag && (abs(dx) > 0.001 || abs(dy) > 0.001) {
                pushUndo()
                hasPushedForDrag = true
            }
            annotations[index].points = origin.points.map {
                NormalizedPoint(x: min(max($0.x + dx, 0), 1),
                                y: min(max($0.y + dy, 0), 1))
            }
            return
        }
        switch annotations[index].kind {
        case .rectangle, .arrow:
            annotations[index].points = [start, point]
        case .freehand:
            let last = annotations[index].points.last ?? start
            let dx = point.x - last.x
            let dy = point.y - last.y
            if hypot(dx, dy) > 0.002 {
                annotations[index].points.append(point)
            }
        case .text:
            break
        }
    }

    func canvasDragEnded() {
        if let id = dragElementID, let index = index(of: id) {
            let element = annotations[index]
            if element.kind == .rectangle || element.kind == .arrow {
                let b = element.boundingRect
                if b.width < 0.004 && b.height < 0.004 {
                    annotations.remove(at: index)
                    selectedID = nil
                }
            }
            if element.kind == .freehand && element.points.count < 2 {
                annotations.remove(at: index)
                selectedID = nil
            }
        }
        dragElementID = nil
        dragOriginElement = nil
        dragStart = nil
        hasPushedForDrag = false
    }

    // MARK: - Editing commands

    func deleteSelected() {
        guard let id = selectedID, let index = index(of: id) else { return }
        pushUndo()
        annotations.remove(at: index)
        selectedID = nil
        textEditingID = nil
    }

    func clearAll() {
        guard !annotations.isEmpty else { return }
        pushUndo()
        annotations.removeAll()
        selectedID = nil
        textEditingID = nil
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        selectedID = nil
        textEditingID = nil
        textUndoPushed = false
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        selectedID = nil
        textEditingID = nil
        textUndoPushed = false
    }

    private func pushUndo() {
        undoStack.append(annotations)
        if undoStack.count > 100 { undoStack.removeFirst(undoStack.count - 100) }
        redoStack.removeAll()
    }

    private func index(of id: UUID) -> Int? {
        annotations.firstIndex(where: { $0.id == id })
    }
}
