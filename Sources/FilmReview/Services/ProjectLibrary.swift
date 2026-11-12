import Foundation

struct ReviewVersion: Codable, Identifiable {
    let id: UUID
    let name: String
}

struct LibraryProject: Codable, Identifiable {
    let id: UUID
    var name: String
    var versions: [ReviewVersion]
    var updatedAt: Date
}

struct ProjectLibrary {
    let root: URL

    init(root: URL = Self.defaultRoot) {
        self.root = root
    }

    static var defaultRoot: URL {
        if let path = ProcessInfo.processInfo.environment["FILMREVIEW_LIBRARY_PATH"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL.applicationSupportDirectory.appendingPathComponent("FilmReview/Library", isDirectory: true)
    }

    func list() throws -> [LibraryProject] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        return try directories.filter { UUID(uuidString: $0.lastPathComponent) != nil }
            .compactMap { folder in
                let manifest = folder.appendingPathComponent("project.json")
                guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
                let project = try Self.decode(LibraryProject.self, at: manifest)
                guard UUID(uuidString: folder.lastPathComponent) == project.id else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return project
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ project: LibraryProject) throws {
        let folder = directory(for: project.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.write(project, to: folder.appendingPathComponent("project.json"))
    }

    func load(_ version: ReviewVersion, in project: LibraryProject) throws -> ReviewProject {
        try Self.loadReview(at: versionURL(version, in: project))
    }

    func save(_ review: ReviewProject, as version: ReviewVersion, in project: LibraryProject) throws {
        let folder = directory(for: project.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.write(review, to: versionURL(version, in: project))
    }

    static func loadReview(at url: URL) throws -> ReviewProject {
        var review = try decode(ReviewProject.self, at: url)
        guard (1...ReviewProject.currentVersion).contains(review.version) else {
            throw NSError(domain: "FilmReview", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "此审阅文件的版本无法读取。"
            ])
        }
        review.renumber()
        return review
    }

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private static func decode<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: url))
    }

    private func directory(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func versionURL(_ version: ReviewVersion, in project: LibraryProject) -> URL {
        directory(for: project.id).appendingPathComponent(version.id.uuidString + ".filmreview")
    }
}
