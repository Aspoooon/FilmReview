import SwiftUI
import UniformTypeIdentifiers

struct ProjectLibraryView: View {
    @ObservedObject var model: AppModel
    @State private var creating = false
    @State private var newName = ""
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                Text("项目库")
                    .font(.system(size: 30, weight: .semibold))
                Spacer()
                Button {
                    model.chooseProject()
                } label: {
                    Label("导入旧工程", systemImage: "doc.badge.plus")
                }
                .buttonStyle(QuietButtonStyle())

                Button {
                    newName = ""
                    creating = true
                } label: {
                    Label("新建项目", systemImage: "plus")
                }
                .buttonStyle(AccentButtonStyle())
            }

            if model.libraryProjects.isEmpty {
                ContentUnavailableView("还没有审片项目", systemImage: "film.stack",
                                       description: Text("新建项目后，将每轮送审的影片导入同一个项目。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.libraryProjects) { project in
                            Button {
                                model.openLibraryProject(project)
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "film.stack")
                                        .font(.system(size: 19))
                                        .foregroundStyle(Theme.accentBright)
                                        .frame(width: 36)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(project.name)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(Theme.textPrimary)
                                        Text(project.versions.last?.name ?? "等待导入影片")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    .lineLimit(1)
                                    Spacer()
                                    Text("\(project.versions.count) 个版本")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Theme.textSecondary)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Hairline()
                        }
                    }
                    .background(Theme.panel)
                }
            }
        }
        .padding(36)
        .frame(maxWidth: 1100, maxHeight: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if targeted {
                Rectangle().strokeBorder(Theme.accentBright, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.handleDroppedURL(url) }
            }
            return true
        }
        .alert("新建项目", isPresented: $creating) {
            TextField("项目名称", text: $newName)
            Button("取消", role: .cancel) {}
            Button("创建") { model.createProject(named: newName) }
        } message: {
            Text("项目将自动保存在本机项目库。")
        }
    }
}
