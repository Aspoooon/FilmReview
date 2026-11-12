import SwiftUI
import AppKit

extension Notification.Name {
    static let filmReviewOpenVideo = Notification.Name("FilmReview.openVideo")
    static let filmReviewOpenProject = Notification.Name("FilmReview.openProject")
    static let filmReviewSaveProject = Notification.Name("FilmReview.saveProject")
    static let filmReviewSaveProjectAs = Notification.Name("FilmReview.saveProjectAs")
    static let filmReviewAddComment = Notification.Name("FilmReview.addComment")
    static let filmReviewExportPDF = Notification.Name("FilmReview.exportPDF")
    static let filmReviewOpenFileURLs = Notification.Name("FilmReview.openFileURLs")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NotificationCenter.default.post(name: .filmReviewOpenFileURLs, object: urls)
    }
}

@main
struct FilmReviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("FilmReview", id: "review") {
            MainWindowView(model: model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入送审版本…") {
                    NotificationCenter.default.post(name: .filmReviewOpenVideo, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("导入旧审阅文件…") {
                    NotificationCenter.default.post(name: .filmReviewOpenProject, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("保存项目") {
                    NotificationCenter.default.post(name: .filmReviewSaveProject, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("导出当前版本工程副本…") {
                    NotificationCenter.default.post(name: .filmReviewSaveProjectAs, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandMenu("审阅") {
                Button("添加修改意见") {
                    NotificationCenter.default.post(name: .filmReviewAddComment, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("导出 PDF 报告…") {
                    NotificationCenter.default.post(name: .filmReviewExportPDF, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
            }
        }
    }
}

/// Installs a local key monitor for document-style shortcuts that must not
/// hijack typing. Menu shortcuts continue to work through SwiftUI commands.
struct KeyEventMonitor: NSViewRepresentable {
    let handler: (NSEvent) -> Bool

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.handler = handler
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.handler = handler
        nsView.installIfNeeded()
    }

    static func dismantleNSView(_ nsView: MonitorView, coordinator: ()) {
        nsView.uninstall()
    }

    final class MonitorView: NSView {
        var handler: ((NSEvent) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installIfNeeded()
        }

        func installIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, window.isKeyWindow else { return event }
                if window.attachedSheet != nil { return event }
                if let responder = window.firstResponder, responder is NSTextView { return event }
                if let responder = window.firstResponder, responder is NSTextField { return event }
                if self.handler?(event) == true { return nil }
                return event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
