import SwiftUI
import AppKit
import AVFoundation
import CoreMedia
import UniformTypeIdentifiers

// MARK: - Player stage

struct PlayerStage: View {
    @ObservedObject var model: AppModel
    @State private var targeted = false

    var body: some View {
        ZStack {
            Color.black

            if let project = model.project {
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        if let editor = model.editor {
                            AnnotationToolbar(model: model, editor: editor)
                                .padding(.horizontal, 10)
                                .padding(.top, 8)
                                .padding(.bottom, 5)
                        }

                        GeometryReader { videoGeo in
                            let aspect = max(0.05, project.videoInfo.aspectRatio)
                            let rect = Self.aspectFit(aspect: aspect, in: videoGeo.size)
                            ZStack {
                                PlayerLayerView(player: model.player.player)
                                    .frame(width: videoGeo.size.width, height: videoGeo.size.height)
                                    .opacity(model.editor == nil ? 1 : 0)

                                if let editor = model.editor {
                                    Image(nsImage: editor.image)
                                        .resizable()
                                        .interpolation(.high)
                                        .frame(width: rect.width, height: rect.height)
                                        .position(x: rect.midX, y: rect.midY)

                                    AnnotationCanvas(editor: editor)
                                        .frame(width: rect.width, height: rect.height)
                                        .position(x: rect.midX, y: rect.midY)
                                } else {
                                    if !model.isVideoMissing {
                                        QuickMarkupCanvas(model: model)
                                            .frame(width: rect.width, height: rect.height)
                                            .position(x: rect.midX, y: rect.midY)
                                        if let comment = model.nearbyComment {
                                            commentOverlay(comment)
                                        }
                                    }

                                    VStack {
                                        HStack {
                                            Spacer()
                                            infoBadges(project: project)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.top, 10)
                                        Spacer()
                                    }
                                    .allowsHitTesting(false)

                                    if model.isVideoMissing {
                                        missingVideoOverlay
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(targeted ? Theme.accent : Color.white.opacity(0.06),
                              lineWidth: targeted ? 1.5 : 1)
        )
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            handleDrop(providers)
        }
    }

    private func commentOverlay(_ comment: ReviewComment) -> some View {
        VStack {
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(comment.timecode(fps: model.fps))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textSecondary)
                Text(comment.note.isEmpty ? "画面标注" : comment.note)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 6))
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func infoBadges(project: ReviewProject) -> some View {
        HStack(spacing: 5) {
            badge(project.videoInfo.resolutionLabel)
            badge(project.videoInfo.frameRateLabel)
            badge(project.videoInfo.aspectLabel)
            if project.videoInfo.isPortrait {
                badge("竖屏", tint: Theme.accentBright)
            }
        }
        .opacity(0.85)
    }

    private func badge(_ text: String, tint: Color = Theme.textSecondary) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.black.opacity(0.45))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
            )
    }

    private var missingVideoOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.accentBright)
            Text("找不到源视频")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("视频可能被移动或重命名。修改意见和截图仍然保留。")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
            Button("重新关联视频…") { model.relinkVideo() }
                .buttonStyle(AccentButtonStyle())
                .padding(.top, 2)
        }
        .padding(26)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.panel.opacity(0.94))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.borderStrong, lineWidth: 1))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.55))
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard model.editor == nil, let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                model.handleDroppedURL(url)
            }
        }
        return true
    }

    static func aspectFit(aspect: CGFloat, in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        var width = size.width
        var height = width / aspect
        if height > size.height {
            height = size.height
            width = height * aspect
        }
        return CGRect(x: (size.width - width) / 2,
                      y: (size.height - height) / 2,
                      width: width,
                      height: height)
    }
}

private struct QuickMarkupCanvas: View {
    @ObservedObject var model: AppModel
    @State private var dragTime: CMTime?
    @State private var preview: AnnotationElement?

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let marks = model.player.isSeeking ? [] : model.playheadComments.flatMap(\.annotations)
                context.drawAnnotations(marks + (preview.map { [$0] } ?? []),
                                        in: CGRect(origin: .zero, size: size))
            }
            .contentShape(Rectangle())
            .accessibilityLabel("审片画面，可拖拽画框")
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .local)
                    .onChanged { value in
                        guard model.canQuickAnnotate else { return }
                        if dragTime == nil { dragTime = model.player.pinReviewTime() }
                        preview = rectangle(for: value, in: geo.size)
                    }
                    .onEnded { value in
                        defer {
                            dragTime = nil
                            preview = nil
                        }
                        let mark = rectangle(for: value, in: geo.size)
                        guard let dragTime,
                              mark.boundingRect.width * geo.size.width >= 5,
                              mark.boundingRect.height * geo.size.height >= 5 else { return }
                        model.saveQuickRectangle(mark, time: dragTime)
                    }
            )
        }
    }

    private func rectangle(for value: DragGesture.Value, in size: CGSize) -> AnnotationElement {
        AnnotationElement(kind: .rectangle, points: [
            NormalizedPoint(value.startLocation, in: size),
            NormalizedPoint(value.location, in: size)
        ])
    }
}

// MARK: - AVPlayerLayer host

struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerHostView, context: Context) {
        if nsView.playerLayer.player !== player {
            nsView.playerLayer.player = player
        }
    }

    final class PlayerHostView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = playerLayer
            playerLayer.videoGravity = .resizeAspect
            playerLayer.backgroundColor = NSColor.black.cgColor
            playerLayer.needsDisplayOnBoundsChange = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var isFlipped: Bool { true }
    }
}

// MARK: - Annotation canvas

struct AnnotationCanvas: View {
    @ObservedObject var editor: AnnotationEditor
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                context.drawAnnotations(editor.annotations,
                                        in: CGRect(origin: .zero, size: size),
                                        selectedID: editor.selectedID)
            }
            .contentShape(Rectangle())
            .onHover { inside in
                if inside && editor.tool != .select {
                    NSCursor.crosshair.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        if !dragging {
                            dragging = true
                            editor.canvasDragBegan(at: NormalizedPoint(value.startLocation, in: geo.size),
                                                   canvasSize: geo.size)
                        }
                        editor.canvasDragChanged(to: NormalizedPoint(value.location, in: geo.size))
                    }
                    .onEnded { value in
                        if dragging {
                            editor.canvasDragChanged(to: NormalizedPoint(value.location, in: geo.size))
                            editor.canvasDragEnded()
                        }
                        dragging = false
                    }
            )
        }
    }
}

// MARK: - Annotation toolbar

private struct AnnotationToolbar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var editor: AnnotationEditor
    @State private var showCancelConfirm = false
    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 5, height: 5)
                    Text(editor.mode == .add ? "添加意见" : "编辑意见")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize()
                    Text(Timecode.string(seconds: editor.timeSeconds, fps: model.fps))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize()
                }

                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 18)

                ForEach(AnnotationTool.allCases) { tool in
                    toolButton(tool)
                }

                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 18)

                ForEach(AnnotationPalette.colors, id: \.self) { hex in
                    colorSwatch(hex)
                }

                Spacer(minLength: 4)

                IconButton(symbol: "arrow.uturn.backward", help: "撤销 (⌘Z)",
                           size: 11, disabled: !editor.canUndo) { editor.undo() }
                IconButton(symbol: "arrow.uturn.forward", help: "重做 (⇧⌘Z)",
                           size: 11, disabled: !editor.canRedo) { editor.redo() }
                IconButton(symbol: "trash", help: "删除选中标注 (Delete)",
                           size: 11, disabled: editor.selectedID == nil) { editor.deleteSelected() }
                IconButton(symbol: "eraser", help: "清除当前标注",
                           size: 11, disabled: editor.annotations.isEmpty) { editor.clearAll() }
            }

            HStack(spacing: 8) {
                Image(systemName: "lineweight")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textTertiary)
                Slider(value: Binding(get: { editor.lineWidth },
                                      set: { editor.applyLineWidth($0) }),
                       in: 1...14) { editing in
                    if editing { editor.beginStyleEdit() }
                }
                .controlSize(.mini)
                .frame(width: 96)
                Text(String(format: "%.1f", editor.lineWidth))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 24, alignment: .leading)

                if editor.selectedElement?.kind == .text {
                    Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 14)
                    Text("字号")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textTertiary)
                    Slider(value: Binding(get: { editor.fontSize },
                                          set: { editor.applyFontSize($0) }),
                           in: 18...96) { editing in
                        if editing { editor.beginStyleEdit() }
                    }
                    .controlSize(.mini)
                    .frame(width: 76)
                } else {
                    Text(editor.selectedID == nil ? "选择对象后可调整颜色与粗细" : "已选中标注")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Button("取消") { requestCancel() }
                    .buttonStyle(QuietButtonStyle())
                    .fixedSize()
                Button("保存意见") { model.saveEditor() }
                    .buttonStyle(AccentButtonStyle())
                    .fixedSize()
            }

            if editor.selectedElement?.kind == .text {
                HStack(spacing: 6) {
                    Image(systemName: "textformat")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.accentBright)
                    TextField("输入标注文字", text: Binding(
                        get: { editor.selectedElement?.text ?? "" },
                        set: { editor.updateSelectedText($0) }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($textFocused)
                    .frame(width: 260)
                    Button("完成") {
                        textFocused = false
                        editor.textEditingID = nil
                    }
                    .buttonStyle(QuietButtonStyle())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.black.opacity(0.55))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Theme.borderStrong, lineWidth: 0.5))
                )
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.95))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.borderStrong, lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        )
        .onChange(of: editor.textEditingID) { _, newValue in
            if newValue != nil { textFocused = true }
        }
        .confirmationDialog("放弃本次标注？", isPresented: $showCancelConfirm) {
            Button("放弃更改", role: .destructive) { model.cancelEditor() }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("尚未保存的标注和备注会丢失。")
        }
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        Button {
            editor.chooseTool(tool)
        } label: {
            Image(systemName: tool.symbol)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(editor.tool == tool ? .white : Theme.textSecondary)
                .frame(width: 25, height: 23)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(editor.tool == tool ? Theme.accent : Color.white.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .help(tool.title)
    }

    private func colorSwatch(_ hex: String) -> some View {
        let color = Color(nsColor: NSColor(hex: hex) ?? .systemRed)
        return Button {
            editor.applyColor(hex)
        } label: {
            Circle()
                .fill(color)
                .frame(width: 14, height: 14)
                .overlay(
                    Circle().strokeBorder(
                        editor.colorHex == hex ? Color.white : Color.white.opacity(0.35),
                        lineWidth: editor.colorHex == hex ? 1.6 : 0.8
                    )
                )
                .padding(2)
        }
        .buttonStyle(.plain)
        .help("标注颜色")
    }

    private func requestCancel() {
        if editor.hasChanges {
            showCancelConfirm = true
        } else {
            model.cancelEditor()
        }
    }
}

// MARK: - Transport bar

struct TransportBar: View {
    @ObservedObject var model: AppModel
    @State private var showJump = false
    @State private var jumpText = ""
    @State private var jumpError: String?

    private var player: PlayerController { model.player }

    var body: some View {
        GeometryReader { geo in
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                IconButton(symbol: "backward.frame", help: "上一帧 (←)", size: 16) {
                    player.step(byFrames: -1)
                }
                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 35)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.accent)
                        )
                }
                .buttonStyle(.plain)
                .help(player.isPlaying ? "暂停 (Space)" : "播放 (Space)")
                IconButton(symbol: "forward.frame", help: "下一帧 (→)", size: 16) {
                    player.step(byFrames: 1)
                }
            }

            Button {
                jumpText = player.currentTimecode
                jumpError = nil
                showJump = true
            } label: {
                HStack(spacing: 6) {
                    Text(player.currentTimecode)
                        .font(Theme.monoLarge)
                        .foregroundStyle(Theme.textPrimary)
                    Text("/ \(player.durationTimecode)")
                        .font(Theme.monoSmall)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                )
            }
            .buttonStyle(.plain)
            .help("点击输入时间码跳转")
            .popover(isPresented: $showJump, arrowEdge: .bottom) {
                jumpPopover
            }

            Spacer(minLength: 8)

            Button {
                model.addComment()
            } label: {
                Label("标注工具", systemImage: "pencil.tip")
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(!model.canQuickAnnotate)
            .help("打开箭头、文字和画笔工具 (⌘N)")

            if model.isPreparingComment {
                ProgressView()
                    .controlSize(.mini)
            }

            HStack(spacing: 5) {
                IconButton(symbol: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                           help: player.isMuted ? "取消静音" : "静音",
                           size: 11) {
                    player.toggleMute()
                }
                Slider(value: Binding(get: { Double(player.volume) },
                                      set: { player.volume = Float($0) }),
                       in: 0...1)
                    .controlSize(.mini)
                    .frame(width: 68)
                    .help("音量")
            }
            .frame(width: 118)

            if geo.size.width > 850 {
                Text("拖拽画框 · 回车写意见")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panel)
        }
        .frame(height: 56)
    }

    private var jumpPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("跳转到时间码")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("格式 HH:MM:SS:FF")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
            TextField("00:00:00:00", text: $jumpText)
                .textFieldStyle(.roundedBorder)
                .font(Theme.mono)
                .frame(width: 190)
                .onSubmit { performJump() }
            if let jumpError {
                Text(jumpError)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accentBright)
            }
            HStack {
                Button("当前帧") {
                    jumpText = player.currentTimecode
                }
                .buttonStyle(QuietButtonStyle())
                Spacer()
                Button("跳转") { performJump() }
                    .buttonStyle(AccentButtonStyle())
            }
        }
        .padding(14)
        .frame(width: 230)
    }

    private func performJump() {
        guard let seconds = Timecode.parseTimecode(jumpText, fps: model.fps) else {
            jumpError = "无法识别这个时间码"
            return
        }
        guard seconds <= player.duration + 0.001 else {
            jumpError = "超出视频时长"
            return
        }
        player.pause()
        player.seek(toSeconds: seconds, exact: true)
        showJump = false
    }
}
