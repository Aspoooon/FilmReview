import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

struct ExportPDFView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var fileName: String = ""
    @State private var directory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory())
    @State private var pdfData: Data?
    @State private var isGenerating = true
    @State private var generationError: String?
    @State private var isExporting = false

    private var defaultStem: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let base = model.projectName == model.versionName
            ? model.projectName : model.projectName + "_" + model.versionName
        return "\(base)_修改意见_\(formatter.string(from: Date()))"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            HStack(spacing: 0) {
                form
                    .frame(width: 340)
                    .background(Theme.panel)
                Hairline().frame(width: 1, height: nil)
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1040, minHeight: 680)
        .background(Theme.background)
        .onAppear {
            if fileName.isEmpty { fileName = defaultStem }
            generate()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.accent.opacity(0.16))
                Image(systemName: "doc.richtext")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.accentBright)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("导出 PDF 修改意见报告")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("按时间码排序 · 包含原始画面截图与矢量标注")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(Theme.panel)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "文件名")
                    HStack(spacing: 5) {
                        TextField("报告文件名", text: $fileName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Theme.background.opacity(0.7))
                            )
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Theme.border, lineWidth: 1))
                        Text(".pdf")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "保存位置")
                    Button {
                        chooseDirectory()
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "folder")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Theme.textSecondary)
                            Text(abbreviatedPath(directory))
                                .font(.system(size: 10.5))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text("更改…")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Theme.accentBright)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Theme.background.opacity(0.7))
                        )
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 7) {
                    SectionLabel(text: "报告内容")
                    infoRow("项目", model.projectName)
                    infoRow("源视频", model.project?.videoInfo.fileName ?? "—")
                    infoRow("影片时长", Timecode.clockString(seconds: model.project?.videoInfo.durationSeconds ?? 0))
                    infoRow("修改意见", "\(model.commentCount) 条")
                    infoRow("页面", "A4 竖版 · 左图右文")
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1))
                )
            }
            .padding(18)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                if let generationError {
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text(generationError)
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(Theme.accentBright)
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 9))
                        Text(isGenerating ? "正在生成预览…" : "预览已就绪")
                            .font(.system(size: 9.5))
                    }
                    .foregroundStyle(Theme.textTertiary)
                }

                HStack(spacing: 8) {
                    Button("取消") { dismiss() }
                        .buttonStyle(QuietButtonStyle())
                    Spacer()
                    Button {
                        exportPDF()
                    } label: {
                        HStack(spacing: 6) {
                            if isExporting {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.down.doc")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text("导出 PDF")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(isGenerating || pdfData == nil || isExporting || fileName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(18)
            .background(Theme.panel)
        }
    }

    private var preview: some View {
        ZStack {
            Color(red: 0.035, green: 0.035, blue: 0.04)
            if isGenerating {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在排版 PDF…")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else if let pdfData {
                PDFKitRepresentedView(data: pdfData)
                    .padding(14)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Theme.textTertiary)
                    Text("无法生成预览")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func generate() {
        guard let project = model.project else {
            generationError = "没有可导出的项目。"
            isGenerating = false
            return
        }
        let title = model.projectName
        isGenerating = true
        generationError = nil
        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try PDFReportGenerator.generate(project: project, title: title)
                }.value
                await MainActor.run {
                    self.pdfData = data
                    self.isGenerating = false
                }
            } catch {
                await MainActor.run {
                    self.generationError = error.localizedDescription
                    self.isGenerating = false
                }
            }
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择 PDF 保存位置"
        panel.prompt = "选择"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = directory
        if panel.runModal() == .OK, let url = panel.url {
            directory = url
        }
    }

    private func exportPDF() {
        guard let data = pdfData else { return }
        var stem = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if stem.lowercased().hasSuffix(".pdf") {
            stem = String(stem.dropLast(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !stem.isEmpty else { return }
        let safeStem = model.sanitizeFileName(stem)
        let target = directory.appendingPathComponent("\(safeStem).pdf")

        if FileManager.default.fileExists(atPath: target.path) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "文件已存在"
            alert.informativeText = "「\(target.lastPathComponent)」已经存在，是否覆盖？"
            alert.addButton(withTitle: "覆盖")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        isExporting = true
        do {
            try data.write(to: target, options: [.atomic])
            model.recordExport()
            model.toast("PDF 已导出：\(target.lastPathComponent)")
            dismiss()
        } catch {
            generationError = "无法写入 PDF：\(error.localizedDescription)"
            isExporting = false
        }
    }

    private func abbreviatedPath(_ url: URL) -> String {
        let home = NSHomeDirectory()
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

struct PDFKitRepresentedView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.backgroundColor = NSColor(red: 0.035, green: 0.035, blue: 0.04, alpha: 1)
        view.document = PDFDocument(data: data)
        context.coordinator.lastHash = data.hashValue
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        let hash = data.hashValue
        guard context.coordinator.lastHash != hash else { return }
        context.coordinator.lastHash = hash
        nsView.document = PDFDocument(data: data)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastHash: Int?
    }
}
