import Foundation
import AppKit
import Combine
import CoreMedia
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let filmReviewProject = UTType(exportedAs: "com.filmreview.project", conformingTo: .json)
}

@MainActor
final class AppModel: ObservableObject {
    let player = PlayerController()
    let thumbnails = ThumbnailService()

    @Published private(set) var project: ReviewProject?
    @Published private(set) var libraryProjects: [LibraryProject] = []
    @Published private(set) var activeProject: LibraryProject?
    @Published private(set) var activeVersion: ReviewVersion?
    @Published private(set) var showsLibrary = true
    @Published var quickNote = ""
    @Published private(set) var quickNoteTime: CMTime?
    @Published var composerFocusRequest: UUID?
    @Published private(set) var isDirty = false
    @Published var selectedCommentID: UUID?
    @Published private(set) var editor: AnnotationEditor?
    @Published private(set) var isPreparingComment = false
    @Published private(set) var busyMessage: String?
    @Published var errorMessage: String?
    @Published var toastMessage: String?
    @Published var isExportPresented = false
    @Published private(set) var isVideoMissing = false
    @Published var isRightPanelVisible = true
    @Published var panelWidth: CGFloat = 360
    @Published private(set) var didBootstrap = false

    private var cancellables = Set<AnyCancellable>()
    private var autosaveTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var terminateObserver: NSObjectProtocol?
    private let library = ProjectLibrary()
    private var editorChanges: AnyCancellable?

    init() {
        player.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        thumbnails.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        player.$videoInfo
            .dropFirst()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.saveOnTerminate()
            }
        }
    }

    deinit {
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
        }
    }

    // MARK: - Derived state

    var comments: [ReviewComment] { project?.comments ?? [] }

    var commentCount: Int { project?.comments.count ?? 0 }

    var selectedComment: ReviewComment? {
        guard let id = selectedCommentID else { return nil }
        return project?.comments.first(where: { $0.id == id })
    }

    var videoURL: URL? {
        guard let project else { return nil }
        return URL(fileURLWithPath: project.videoPath)
    }

    var projectName: String { activeProject?.name ?? "影片审阅" }
    var versionName: String { activeVersion?.name ?? "" }
    var canQuickAnnotate: Bool {
        project != nil && editor == nil && !isVideoMissing && !isPreparingComment && busyMessage == nil
    }

    var playheadComments: [ReviewComment] {
        guard !isVideoMissing else { return [] }
        let tolerance = 0.5 / max(fps, 1)
        return comments.filter { abs($0.timeSeconds - player.currentSeconds) <= tolerance }
    }

    var nearbyComment: ReviewComment? {
        guard !isVideoMissing else { return nil }
        let seconds = player.currentSeconds
        return playheadComments.first ?? comments.min {
            abs($0.timeSeconds - seconds) < abs($1.timeSeconds - seconds)
        }.flatMap { abs($0.timeSeconds - seconds) <= 0.45 ? $0 : nil }
    }

    var fps: Double { project?.videoInfo.frameRate ?? 30 }

    var isEditingComment: Bool { editor != nil }

    var hasProject: Bool { project != nil }

    // MARK: - Bootstrap

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        refreshLibrary()
    }

    func refreshLibrary() {
        do {
            libraryProjects = try library.list()
        } catch {
            present(error)
        }
    }

    func showLibrary() {
        guard prepareToSwitch() else { return }
        player.pause()
        refreshLibrary()
        showsLibrary = true
    }

    func createProject(named name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, prepareToSwitch() else { return }
        let folder = LibraryProject(id: UUID(), name: name, versions: [], updatedAt: Date())
        do {
            try library.save(folder)
            activate(folder, version: nil, review: nil)
            refreshLibrary()
        } catch {
            present(error)
        }
    }

    func openLibraryProject(_ folder: LibraryProject) {
        guard prepareToSwitch() else { return }
        do {
            let version = folder.versions.last
            let review = try version.map { try library.load($0, in: folder) }
            activate(folder, version: version, review: review)
        } catch {
            present(error)
        }
    }

    func switchVersion(_ version: ReviewVersion) {
        guard let folder = activeProject, version.id != activeVersion?.id,
              folder.versions.contains(where: { $0.id == version.id }),
              prepareToSwitch() else { return }
        do {
            let review = try library.load(version, in: folder)
            activate(folder, version: version, review: review)
        } catch {
            present(error)
        }
    }

    private func activate(_ folder: LibraryProject, version: ReviewVersion?, review: ReviewProject?) {
        autosaveTask?.cancel()
        activeProject = folder
        activeVersion = version
        project = review
        selectedCommentID = nil
        closeEditorDiscarding()
        clearQuickNote()
        isDirty = false
        player.detach()
        thumbnails.reset()
        isVideoMissing = false
        reloadVideoForCurrentProject()
        showsLibrary = false
    }

    func chooseVideo() {
        guard activeProject != nil, !showsLibrary, !isPreparingComment, busyMessage == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "导入送审版本"
        panel.prompt = "导入"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .audiovisualContent]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await importVideo(url: url) }
    }

    func chooseProject() {
        guard !isPreparingComment, busyMessage == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "导入旧审阅文件"
        panel.prompt = "导入副本"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.filmReviewProject, .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { importLegacy(url) }
    }

    func handleDroppedURL(_ url: URL) {
        if url.pathExtension.lowercased() == "filmreview" {
            importLegacy(url)
        } else if VideoInspector.isVideoFile(url) {
            Task { await importVideo(url: url) }
        } else {
            errorMessage = "请拖入可播放的视频或 .filmreview 审阅文件。"
        }
    }

    private func importLegacy(_ url: URL) {
        do {
            let review = try ProjectLibrary.loadReview(at: url)
            guard prepareToSwitch() else { return }
            try appendVersion(review, useActiveProject: !showsLibrary)
        } catch {
            present(error)
        }
    }

    func importVideo(url: URL) async {
        guard VideoInspector.isVideoFile(url), prepareToSwitch() else { return }
        busyMessage = "正在读取视频…"
        defer { busyMessage = nil }

        do {
            let info = try await VideoInspector.inspect(url: url)
            let review = ReviewProject(name: url.deletingPathExtension().lastPathComponent,
                                       videoPath: url.path,
                                       videoBookmark: VideoInspector.bookmark(for: url),
                                       videoInfo: info)
            try appendVersion(review, useActiveProject: !showsLibrary)
        } catch {
            present(error)
        }
    }

    private func appendVersion(_ review: ReviewProject, useActiveProject: Bool) throws {
        let now = Date()
        var folder = (useActiveProject ? activeProject : nil)
            ?? LibraryProject(id: UUID(), name: review.name, versions: [], updatedAt: now)
        let version = ReviewVersion(id: UUID(), name: review.name)
        folder.versions.append(version)
        folder.updatedAt = now
        try library.save(review, as: version, in: folder)
        try library.save(folder)
        activate(folder, version: version, review: review)
        refreshLibrary()
        toast("已导入版本 · \(version.name)")
    }

    private func prepareToSwitch() -> Bool {
        guard !isPreparingComment, busyMessage == nil else { return false }
        if editor != nil || !quickNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let alert = NSAlert()
            alert.messageText = "当前还有未提交的意见"
            alert.addButton(withTitle: "继续编辑")
            alert.addButton(withTitle: "放弃并切换")
            guard alert.runModal() == .alertSecondButtonReturn else { return false }
            closeEditorDiscarding()
            clearQuickNote()
        }
        return !isDirty || saveProject()
    }

    private func reloadVideoForCurrentProject() {
        guard var project else { return }
        var url = URL(fileURLWithPath: project.videoPath)
        if !FileManager.default.fileExists(atPath: url.path),
           let bookmark = project.videoBookmark,
           let resolved = VideoInspector.resolveBookmark(bookmark),
           FileManager.default.fileExists(atPath: resolved.path) {
            url = resolved
            project.videoPath = url.path
            self.project = project
        }
        if FileManager.default.fileExists(atPath: url.path) {
            isVideoMissing = false
            player.attach(url: url, info: project.videoInfo)
            thumbnails.configure(url: url)
        } else {
            isVideoMissing = true
            player.detach()
            thumbnails.reset()
        }
    }

    @discardableResult
    func saveProject() -> Bool {
        guard let project, let activeProject, let activeVersion else { return true }
        do {
            try library.save(project, as: activeVersion, in: activeProject)
            isDirty = false
            return true
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    func saveProjectAs() -> Bool {
        guard let project else { return false }
        let panel = NSSavePanel()
        panel.title = "导出当前版本工程副本"
        panel.allowedContentTypes = [.filmReviewProject]
        panel.nameFieldStringValue = sanitizeFileName(project.name) + ".filmreview"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try ProjectLibrary.write(project, to: url)
            toast("已导出工程副本")
            return true
        } catch {
            present(error)
            return false
        }
    }

    private func saveOnTerminate() {
        if isDirty { saveProject() }
    }

    func markDirty() {
        guard var project else { return }
        project.updatedAt = Date()
        self.project = project
        isDirty = true
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveProject()
        }
    }

    func setProjectName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var folder = activeProject, folder.name != trimmed else { return }
        folder.name = trimmed
        folder.updatedAt = Date()
        do {
            try library.save(folder)
            activeProject = folder
            refreshLibrary()
        } catch {
            present(error)
        }
    }

    // MARK: - Relink

    func relinkVideo() {
        guard project != nil, !isPreparingComment, busyMessage == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "重新关联源视频"
        panel.prompt = "关联"
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .audiovisualContent]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            busyMessage = "正在校验视频…"
            defer { busyMessage = nil }
            do {
                let info = try await VideoInspector.inspect(url: url)
                guard var project else { return }
                let oldDuration = project.videoInfo.durationSeconds
                project.videoPath = url.path
                project.videoBookmark = VideoInspector.bookmark(for: url)
                project.videoInfo = info
                self.project = project
                isVideoMissing = false
                player.attach(url: url, info: info)
                thumbnails.configure(url: url)
                markDirty()
                if abs(oldDuration - info.durationSeconds) > 1.0 {
                    toast("已重新关联。注意：新视频时长与原来不同，请核对意见时间码。")
                } else {
                    toast("已重新关联源视频")
                }
            } catch {
                present(error)
            }
        }
    }

    // MARK: - Comments

    func pinQuickNote() {
        guard canQuickAnnotate, quickNoteTime == nil else { return }
        quickNoteTime = player.pinReviewTime()
    }

    func clearQuickNote() {
        quickNote = ""
        quickNoteTime = nil
        composerFocusRequest = nil
    }

    func submitQuickNote() {
        let note = quickNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty, canQuickAnnotate else { return }
        captureQuickComment(note: note, annotation: nil, time: quickNoteTime ?? player.pinReviewTime())
    }

    func saveQuickRectangle(_ annotation: AnnotationElement, time: CMTime) {
        captureQuickComment(note: "", annotation: annotation, time: time)
    }

    private func captureQuickComment(note: String, annotation: AnnotationElement?, time: CMTime) {
        guard canQuickAnnotate, let videoURL else { return }
        isPreparingComment = true
        Task {
            defer { isPreparingComment = false }
            do {
                let frame = try await FrameExporter.capture(videoURL: videoURL, at: time)
                guard var review = project else { return }
                let seconds = frame.actualTime.seconds
                let tolerance = min(0.001, 0.25 / max(fps, 1))
                let now = Date()
                let id: UUID
                if let index = review.comments.lastIndex(where: { abs($0.timeSeconds - seconds) <= tolerance }) {
                    if !note.isEmpty {
                        let existing = review.comments[index].note
                        review.comments[index].note = existing.isEmpty ? note : existing + "\n" + note
                    }
                    if let annotation { review.comments[index].annotations.append(annotation) }
                    review.comments[index].updatedAt = now
                    id = review.comments[index].id
                } else {
                    let comment = ReviewComment(number: review.comments.count + 1,
                                                time: frame.actualTime,
                                                timeSeconds: seconds,
                                                note: note,
                                                annotations: annotation.map { [$0] } ?? [],
                                                screenshotJPEG: frame.jpegData,
                                                imagePixelWidth: Int(frame.image.size.width),
                                                imagePixelHeight: Int(frame.image.size.height))
                    review.comments.append(comment)
                    id = comment.id
                }
                review.renumber()
                project = review
                selectedCommentID = id
                if !note.isEmpty { clearQuickNote() }
                markDirty()
                saveProject()
            } catch {
                present(error)
            }
        }
    }

    func addComment() {
        guard let project, canQuickAnnotate, !showsLibrary else { return }
        if isVideoMissing || !FileManager.default.fileExists(atPath: project.videoPath) {
            errorMessage = "源视频文件不在原位置。请先重新关联视频，然后再添加修改意见。"
            return
        }
        guard editor == nil else { return }
        let time = player.pinReviewTime()
        let url = URL(fileURLWithPath: project.videoPath)
        isPreparingComment = true
        Task {
            defer { isPreparingComment = false }
            do {
                let captured = try await FrameExporter.capture(videoURL: url, at: time)
                // Re-seek to the exact captured frame so the locked preview and
                // the stored timestamp always agree.
                player.seek(to: captured.actualTime)
                openEditor(mode: .add,
                           commentID: nil,
                           imageData: captured.jpegData,
                           image: captured.image,
                           time: captured.actualTime,
                           timeSeconds: captured.actualTime.seconds,
                           note: "",
                           annotations: [])
            } catch {
                present(error)
            }
        }
    }

    func editAnnotations(for commentID: UUID) {
        guard editor == nil, !isPreparingComment else { return }
        guard let comment = project?.comments.first(where: { $0.id == commentID }) else { return }
        guard let image = FrameExporter.nsImage(from: comment.screenshotJPEG) else {
            errorMessage = "这条意见的截图缓存已损坏，无法重新编辑标注。"
            return
        }
        player.pause()
        if !isVideoMissing {
            player.seek(to: comment.time)
        }
        selectedCommentID = commentID
        openEditor(mode: .edit,
                   commentID: commentID,
                   imageData: comment.screenshotJPEG,
                   image: image,
                   time: comment.time,
                   timeSeconds: comment.timeSeconds,
                   note: comment.note,
                   annotations: comment.annotations)
    }

    private func openEditor(mode: AnnotationEditor.Mode,
                            commentID: UUID?,
                            imageData: Data,
                            image: NSImage,
                            time: CMTime,
                            timeSeconds: Double,
                            note: String,
                            annotations: [AnnotationElement]) {
        let editor = AnnotationEditor(mode: mode,
                                      commentID: commentID,
                                      imageData: imageData,
                                      image: image,
                                      time: time,
                                      timeSeconds: timeSeconds,
                                      note: note,
                                      annotations: annotations)
        self.editor = editor
        editorChanges = editor.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
        objectWillChange.send()
    }

    func saveEditor() {
        guard let editor, var project else { return }
        let now = Date()
        if editor.mode == .add {
            var comment = ReviewComment(number: project.comments.count + 1,
                                        time: editor.time,
                                        timeSeconds: editor.timeSeconds,
                                        note: editor.note.trimmingCharacters(in: .whitespacesAndNewlines),
                                        annotations: editor.annotations,
                                        screenshotJPEG: editor.imageData,
                                        imagePixelWidth: Int(editor.image.size.width),
                                        imagePixelHeight: Int(editor.image.size.height),
                                        createdAt: now,
                                        updatedAt: now)
            comment.number = project.comments.count + 1
            project.comments.append(comment)
            project.renumber()
            self.project = project
            selectedCommentID = comment.id
        } else if let id = editor.commentID,
                  let index = project.comments.firstIndex(where: { $0.id == id }) {
            project.comments[index].note = editor.note.trimmingCharacters(in: .whitespacesAndNewlines)
            project.comments[index].annotations = editor.annotations
            project.comments[index].updatedAt = now
            project.renumber()
            self.project = project
            selectedCommentID = id
        }
        closeEditorDiscarding()
        markDirty()
        toast("修改意见已保存")
    }

    func cancelEditor() {
        closeEditorDiscarding()
    }

    private func closeEditorDiscarding() {
        editorChanges = nil
        editor = nil
    }

    func deleteComment(_ id: UUID) {
        guard var project else { return }
        project.comments.removeAll { $0.id == id }
        project.renumber()
        self.project = project
        if selectedCommentID == id { selectedCommentID = nil }
        markDirty()
    }

    func updateNote(_ id: UUID, note: String) {
        guard var project, let index = project.comments.firstIndex(where: { $0.id == id }) else { return }
        guard project.comments[index].note != note else { return }
        project.comments[index].note = note
        project.comments[index].updatedAt = Date()
        self.project = project
        markDirty()
    }

    func selectComment(_ id: UUID, seek: Bool = true) {
        selectedCommentID = id
        guard seek, let comment = project?.comments.first(where: { $0.id == id }) else { return }
        guard !isVideoMissing else { return }
        player.pause()
        player.seek(to: comment.time)
    }

    // MARK: - Export

    func presentExport() {
        guard commentCount > 0, !showsLibrary, !isPreparingComment, editor == nil else { return }
        player.pause()
        isExportPresented = true
    }

    func recordExport() {
        guard var project else { return }
        project.lastExportAt = Date()
        self.project = project
        markDirty()
        toast("PDF 报告已导出")
    }

    // MARK: - UI helpers

    func toast(_ message: String) {
        toastMessage = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
        }
    }

    func present(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    func sanitizeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: " ")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名审阅" : trimmed
    }

    // MARK: - Keyboard

    func handleSpace() {
        guard editor == nil else { return }
        player.togglePlayback()
    }

    func handleArrow(_ direction: Int) {
        guard editor == nil, project != nil else { return }
        player.step(byFrames: direction)
    }

    func handleDeleteKey() {
        guard let editor else { return }
        editor.deleteSelected()
    }

    func handleEscape() {
        guard let editor else { return }
        if editor.tool != .select || editor.selectedID != nil || editor.textEditingID != nil {
            editor.chooseTool(.select)
            editor.selectedID = nil
            editor.textEditingID = nil
        }
    }

    func handleUndo() {
        if let editor, editor.textEditingID == nil {
            editor.undo()
        }
    }

    func handleRedo() {
        if let editor, editor.textEditingID == nil {
            editor.redo()
        }
    }
}
