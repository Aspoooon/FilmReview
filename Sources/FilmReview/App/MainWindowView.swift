import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MainWindowView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                TopBar(model: model)
                Hairline()
                if model.showsLibrary {
                    ProjectLibraryView(model: model)
                } else {
                    workspace
                }
            }

            if let busy = model.busyMessage {
                BusyOverlay(message: busy)
                    .zIndex(20)
            }
        }
        .background(WindowConfigurator())
        .background(
            KeyEventMonitor { event in
                handleKey(event)
            }
        )
        .animation(.easeOut(duration: 0.18), value: model.isRightPanelVisible)
        .task { model.bootstrap() }
        .onReceive(NotificationCenter.default.publisher(for: .filmReviewOpenVideo)) { _ in
            model.chooseVideo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .filmReviewOpenProject)) { _ in
            model.chooseProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: .filmReviewSaveProject)) { _ in
            _ = model.saveProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: .filmReviewSaveProjectAs)) { _ in
            _ = model.saveProjectAs()
        }
        .onReceive(NotificationCenter.default.publisher(for: .filmReviewAddComment)) { _ in
            model.addComment()
        }
        .onReceive(NotificationCenter.default.publisher(for: .filmReviewExportPDF)) { _ in
            model.presentExport()
        }
        .onReceive(NotificationCenter.default.publisher(for: .filmReviewOpenFileURLs)) { notification in
            if let urls = notification.object as? [URL], let first = urls.first {
                model.handleDroppedURL(first)
            }
        }
        .alert("FilmReview", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: $model.isExportPresented) {
            ExportPDFView(model: model)
        }
    }

    private var workspace: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if model.hasProject {
                    PlayerStage(model: model)
                    TransportBar(model: model)
                    TimelineSection(model: model)
                } else {
                    EmptyWorkspace(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.isRightPanelVisible {
                PanelResizeHandle(model: model)
                CommentsPanel(model: model)
                    .frame(width: model.panelWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard !model.showsLibrary else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags.contains(.command) {
            if chars == "z" {
                guard let editor = model.editor, editor.textEditingID == nil else { return false }
                if flags.contains(.shift) {
                    model.handleRedo()
                } else {
                    model.handleUndo()
                }
                return true
            }
            return false
        }

        // Allow modifier-only keys and non-document shortcuts through.
        if !flags.isEmpty && !flags.isSubset(of: [.numericPad, .function]) { return false }

        switch event.keyCode {
        case 36, 76: // Return / keypad Enter
            guard model.canQuickAnnotate else { return false }
            model.isRightPanelVisible = true
            model.composerFocusRequest = UUID()
            return true
        case 49: // Space
            if model.editor == nil {
                model.handleSpace()
            }
            return true
        case 123: // Left
            if model.editor == nil, model.hasProject {
                model.handleArrow(-1)
            }
            return true
        case 124: // Right
            if model.editor == nil, model.hasProject {
                model.handleArrow(1)
            }
            return true
        case 51, 117: // Delete / forward delete
            if model.editor != nil {
                model.handleDeleteKey()
                return true
            }
            return false
        case 53: // Escape
            if model.editor != nil {
                model.handleEscape()
                return true
            }
            return false
        default:
            return false
        }
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @ObservedObject var model: AppModel
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            if model.showsLibrary {
                Text("FilmReview")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            } else {
                Button {
                    model.showLibrary()
                } label: {
                    Label("项目库", systemImage: "square.grid.2x2")
                }
                .buttonStyle(QuietButtonStyle())
                .help("返回项目库")

                TextField("项目名称", text: $nameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(minWidth: 90, idealWidth: 155, maxWidth: 220, alignment: .leading)
                    .focused($nameFocused)
                    .onSubmit { commitName(); nameFocused = false }
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { commitName() }
                    }
                    .onChange(of: model.projectName) { _, name in nameDraft = name }
                    .onAppear { nameDraft = model.projectName }
                    .help("点击重命名项目")

                if let toast = model.toastMessage {
                    Text(toast)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: 150, alignment: .leading)
                }

                if model.isDirty {
                    Image(systemName: "circle.dotted")
                        .foregroundStyle(Theme.accentBright)
                        .help("等待自动保存")
                }

                Spacer(minLength: 10)

                if let folder = model.activeProject,
                   let activeIndex = folder.versions.firstIndex(where: { $0.id == model.activeVersion?.id }) {
                    Menu {
                        ForEach(Array(folder.versions.enumerated().reversed()), id: \.element.id) { index, version in
                            Button {
                                model.switchVersion(version)
                            } label: {
                                if version.id == model.activeVersion?.id {
                                    Label("V\(index + 1) · \(version.name)", systemImage: "checkmark")
                                } else {
                                    Text("V\(index + 1) · \(version.name)")
                                }
                            }
                        }
                    } label: {
                        Label {
                            Text("V\(activeIndex + 1) · \(model.versionName)")
                                .lineLimit(1)
                                .frame(maxWidth: 190, alignment: .leading)
                        } icon: {
                            Image(systemName: "film.stack")
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize(horizontal: true, vertical: false)
                    .font(.system(size: 13))
                    .frame(maxWidth: 240)
                    .help("切换送审版本")
                }

                Button {
                    model.chooseVideo()
                } label: {
                    Label("导入版本", systemImage: "plus")
                }
                .buttonStyle(QuietButtonStyle())
                .help("将视频加入当前项目 (⌘O)")

                Button {
                    model.presentExport()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("导出 PDF")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(!model.hasProject || model.commentCount == 0 || model.editor != nil)
                .opacity(model.hasProject && model.commentCount > 0 && model.editor == nil ? 1 : 0.45)
                .help(model.editor != nil ? "请先保存或取消当前标注" : (model.commentCount > 0 ? "导出图文修改意见 PDF (⌘E)" : "添加修改意见后可导出 PDF"))

                IconButton(symbol: model.isRightPanelVisible ? "sidebar.right" : "sidebar.left",
                           help: model.isRightPanelVisible ? "收起意见面板" : "展开意见面板",
                           size: 12) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        model.isRightPanelVisible.toggle()
                    }
                }
            }
        }
        .padding(.leading, 80)
        .padding(.trailing, 14)
        .frame(height: 58)
        .background(Theme.panel)
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nameDraft = model.projectName
            return
        }
        if trimmed != model.projectName {
            model.setProjectName(trimmed)
        }
        nameDraft = model.projectName
    }
}

// MARK: - Empty state

private struct EmptyWorkspace: View {
    @ObservedObject var model: AppModel
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            VStack(spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                        .frame(width: 96, height: 96)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            targeted ? Theme.accent : Color.white.opacity(0.12),
                            style: StrokeStyle(lineWidth: targeted ? 1.5 : 1, dash: [6, 5])
                        )
                        .frame(width: 156, height: 156)
                    Image(systemName: "film.stack")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(targeted ? Theme.accentBright : Theme.textSecondary)
                }

                VStack(spacing: 8) {
                    Text(targeted ? "松开以导入视频" : "导入第一支送审影片")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("支持 MP4、MOV、ProRes、HEVC 等系统可解码格式\n视频只在本机处理，不会上传")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                HStack(spacing: 10) {
                    Button {
                        model.chooseVideo()
                    } label: {
                        Label("导入版本", systemImage: "plus")
                    }
                    .buttonStyle(AccentButtonStyle())

                    Button {
                        model.chooseProject()
                    } label: {
                        Label("导入旧工程", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(QuietButtonStyle())
                }
                .padding(.top, 4)

                HStack(spacing: 18) {
                    hint(keys: "Space", text: "播放 / 暂停")
                    hint(keys: "← →", text: "逐帧")
                    hint(keys: "Return", text: "写意见")
                    hint(keys: "⌘E", text: "导出 PDF")
                }
                .padding(.top, 10)
            }
            .padding(48)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.panel.opacity(targeted ? 0.8 : 0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(targeted ? Theme.accent.opacity(0.8) : Theme.border,
                                          style: StrokeStyle(lineWidth: 1, dash: targeted ? [] : [7, 6]))
                    )
            )
            .padding(.horizontal, 64)
            .frame(maxWidth: 760)

            Spacer(minLength: 40)

            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 10))
                Text("完全本地运行 · 无需账号 · 不上传视频")
                    .font(.system(size: 10.5))
            }
            .foregroundStyle(Theme.textTertiary)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            handleDrop(providers)
        }
    }

    private func hint(keys: String, text: String) -> some View {
        HStack(spacing: 6) {
            ShortcutHint(text: keys)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                model.handleDroppedURL(url)
            }
        }
        return true
    }
}

// MARK: - Panel resize

private struct PanelResizeHandle: View {
    @ObservedObject var model: AppModel
    @State private var startWidth: CGFloat = 360
    @State private var dragStartWidth: CGFloat?
    @State private var hovering = false

    var body: some View {
        ZStack {
            Theme.panel
            Rectangle()
                .fill(hovering ? Theme.accent.opacity(0.6) : Theme.border)
                .frame(width: 1)
        }
        .frame(width: 9)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = model.panelWidth
                        startWidth = model.panelWidth
                    }
                    let newWidth = startWidth - value.translation.width
                    model.panelWidth = min(max(newWidth, 288), 540)
                }
                .onEnded { _ in
                    dragStartWidth = nil
                }
        )
    }
}

// MARK: - Toast / busy / window

private struct BusyOverlay: View {
    let message: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text(message)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.panelRaised)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Theme.borderStrong, lineWidth: 1))
            )
        }
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(red: 0.055, green: 0.055, blue: 0.062, alpha: 1)
            window.isMovableByWindowBackground = true
            window.minSize = NSSize(width: 1100, height: 720)
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.appearance = NSAppearance(named: .darkAqua)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
