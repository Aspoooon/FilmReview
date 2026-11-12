import SwiftUI
import AppKit

// MARK: - Image cache

final class ReviewImageCache {
    static let shared = ReviewImageCache()
    private let cache = NSCache<NSString, NSImage>()

    func thumbnail(for comment: ReviewComment) -> NSImage? {
        let key = "thumb-\(comment.id.uuidString)-\(comment.updatedAt.timeIntervalSince1970)" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let image = FrameExporter.thumbnail(from: comment.screenshotJPEG, maxPixelSize: 320) else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }

    func composite(for comment: ReviewComment) -> NSImage? {
        let key = "comp-\(comment.id.uuidString)-\(comment.updatedAt.timeIntervalSince1970)" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let image = AnnotationRenderer.composite(screenshotJPEG: comment.screenshotJPEG,
                                                       annotations: comment.annotations,
                                                       maxPixelSize: 2400) else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }
}

// MARK: - Panel

struct CommentsPanel: View {
    @ObservedObject var model: AppModel
    @State private var previewComment: ReviewComment?
    @State private var pendingDelete: ReviewComment?
    @FocusState private var composing: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()

            if let editor = model.editor {
                AnnotationNotePanel(model: model, editor: editor)
            } else if let project = model.project {
                quickComposer
                Hairline()
                if project.comments.isEmpty {
                    emptyState
                } else {
                    commentList
                    if let selected = model.selectedComment {
                        Hairline()
                        noteInspector(for: selected)
                    }
                }
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Theme.textTertiary)
                    Text("导入视频后开始审阅")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }
        }
        .frame(maxHeight: .infinity)
        .background(Theme.panel)
        .onAppear { focusComposerIfRequested() }
        .onChange(of: model.composerFocusRequest) { _, _ in focusComposerIfRequested() }
        .sheet(item: $previewComment) { comment in
            CommentPreviewSheet(model: model, comment: comment) {
                previewComment = nil
            }
        }
        .alert("删除这条修改意见？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { comment in
            Button("删除", role: .destructive) {
                model.deleteComment(comment.id)
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: { comment in
            Text("意见 \(String(format: "%02d", comment.number)) · \(comment.timecode(fps: model.fps))\n删除后无法恢复。")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("修改意见")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if model.hasProject {
                Text("\(model.commentCount) 条")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private var quickComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.quickNoteTime.map { Timecode.string(seconds: $0.seconds, fps: model.fps) }
                     ?? "当前画面")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if model.quickNoteTime != nil {
                    Button("清除") {
                        composing = false
                        model.clearQuickNote()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                }
            }

            HStack(spacing: 8) {
                TextField("输入修改意见", text: $model.quickNote)
                    .font(.system(size: 14))
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(composing ? Theme.accentBright : Theme.borderStrong))
                    .focused($composing)
                    .accessibilityLabel("输入修改意见")
                    .onSubmit { submitNote() }
                    .onChange(of: composing) { _, focused in
                        if focused {
                            model.pinQuickNote()
                        } else if model.quickNote.isEmpty {
                            model.clearQuickNote()
                        }
                    }
                Button {
                    submitNote()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(model.quickNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("保存修改意见")
                .help("保存修改意见 (Return)")
            }
            .disabled(!model.canQuickAnnotate)
        }
        .padding(14)
    }

    private func focusComposerIfRequested() {
        guard model.composerFocusRequest != nil, model.canQuickAnnotate else { return }
        model.composerFocusRequest = nil
        composing = true
    }

    private func submitNote() {
        guard !model.quickNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.submitQuickNote()
        composing = false
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 52, height: 52)
                Image(systemName: "text.bubble")
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
            }
            Text("还没有修改意见")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text("输入意见后按回车，或直接在画面上拖拽画框。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var commentList: some View {
        ScrollView {
            LazyVStack(spacing: 3) {
                ForEach(model.comments) { comment in
                    CommentRow(comment: comment,
                               fps: model.fps,
                               selected: comment.id == model.selectedCommentID) {
                        model.selectComment(comment.id)
                    } onEdit: {
                        model.editAnnotations(for: comment.id)
                    } onPreview: {
                        previewComment = comment
                    } onDelete: {
                        pendingDelete = comment
                    }
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 7)
        }
        .frame(maxHeight: .infinity)
    }

    private func noteInspector(for comment: ReviewComment) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                SectionLabel(text: "修改备注")
                Text(comment.timecode(fps: model.fps))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("查看截图") {
                    previewComment = comment
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                Button("编辑标注") {
                    model.editAnnotations(for: comment.id)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accentBright)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { comment.note },
                    set: { model.updateNote(comment.id, note: $0) }
                ))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .background(Theme.background.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                if comment.note.isEmpty {
                    Text("输入文字修改意见…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 7)
                        .padding(.leading, 6)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 102)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )

            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 9))
                Text("修改自动保存")
                    .font(.system(size: 9))
                Spacer()
                Text("\(comment.annotations.count) 个标注")
                    .font(.system(size: 9))
            }
            .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 11)
        .background(Theme.panel)
    }
}

// MARK: - Row

private struct CommentRow: View {
    let comment: ReviewComment
    let fps: Double
    let selected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onPreview: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.white.opacity(0.04))
                            .overlay(Image(systemName: "photo")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textTertiary))
                    }
                }
                .frame(width: 86, height: 50)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                if !comment.annotations.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "pencil.tip")
                            .font(.system(size: 6.5, weight: .bold))
                        Text("\(comment.annotations.count)")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3.5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Theme.accent))
                    .padding(3)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(String(format: "%02d", comment.number))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(selected ? .white : Theme.textSecondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(selected ? Theme.accent : Color.white.opacity(0.07))
                        )
                    Text(comment.timecode(fps: fps))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    Spacer(minLength: 0)
                }
                Text(comment.note.isEmpty ? "画面标注" : comment.note)
                    .font(.system(size: 13))
                    .foregroundStyle(comment.note.isEmpty ? Theme.textTertiary : Theme.textPrimary.opacity(0.9))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 1)

            Spacer(minLength: 0)
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? Theme.accent.opacity(0.13) : (hovering ? Color.white.opacity(0.035) : Color.clear))
        )
        .overlay(alignment: .leading) {
            if selected {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.accent)
                    .frame(width: 2)
                    .padding(.vertical, 7)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("定位到该画面") { onSelect() }
            Button("查看截图与标注") { onPreview() }
            Button("编辑标注") { onEdit() }
            Divider()
            Button("删除意见", role: .destructive) { onDelete() }
        }
        .task(id: comment.updatedAt) {
            thumbnail = ReviewImageCache.shared.thumbnail(for: comment)
        }
    }
}

// MARK: - Annotation note editor panel

private struct AnnotationNotePanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var editor: AnnotationEditor
    @State private var showCancelConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.tip.crop.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accentBright)
                    Text(editor.mode == .add ? "新修改意见" : "编辑意见")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(Timecode.string(seconds: editor.timeSeconds, fps: model.fps))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text("画面已锁定 · \(editor.annotations.count) 个标注")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 9)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $editor.note)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Theme.background.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                if editor.note.isEmpty {
                    Text("输入这条修改意见…\n例如：这里人物眼神偏离，请替换为第 3 条素材。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .lineSpacing(3)
                        .padding(.top, 7)
                        .padding(.leading, 6)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .padding(.horizontal, 12)

            Text("在左侧画面框选、画箭头、写字或自由画笔。标注会以矢量数据保存，可随时重新编辑。")
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textTertiary)
                .lineSpacing(2)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            HStack(spacing: 8) {
                Button("取消") {
                    if editor.hasChanges {
                        showCancelConfirm = true
                    } else {
                        model.cancelEditor()
                    }
                }
                .buttonStyle(QuietButtonStyle())
                Spacer()
                Button("保存意见") { model.saveEditor() }
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(12)
        }
        .frame(maxHeight: .infinity)
        .confirmationDialog("放弃本次标注？", isPresented: $showCancelConfirm) {
            Button("放弃更改", role: .destructive) { model.cancelEditor() }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("尚未保存的标注和备注会丢失。")
        }
    }
}

// MARK: - Preview sheet

private struct CommentPreviewSheet: View {
    @ObservedObject var model: AppModel
    let comment: ReviewComment
    let onClose: () -> Void
    @State private var image: NSImage?
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(String(format: "意见 %02d", comment.number))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(comment.timecode(fps: model.fps))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.accentBright)
                Spacer()
                Button("编辑标注") {
                    onClose()
                    model.editAnnotations(for: comment.id)
                }
                .buttonStyle(QuietButtonStyle())
                Button("关闭") { onClose() }
                    .buttonStyle(AccentButtonStyle())
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(Theme.panel)

            Hairline()

            ZStack {
                Color.black
                if loading {
                    ProgressView()
                        .controlSize(.small)
                } else if let image {
                    GeometryReader { geo in
                        let rect = PlayerStage.aspectFit(
                            aspect: image.size.width / max(1, image.size.height),
                            in: CGSize(width: geo.size.width - 32, height: geo.size.height - 28)
                        )
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                } else {
                    Text("无法读取截图")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !comment.note.isEmpty {
                Hairline()
                ScrollView {
                    Text(comment.note)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textPrimary)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .textSelection(.enabled)
                }
                .frame(height: 120)
                .background(Theme.panel)
            }
        }
        .frame(minWidth: 880, minHeight: 620)
        .task {
            image = ReviewImageCache.shared.composite(for: comment)
            loading = false
        }
    }
}
