import Foundation

struct SessionStorage: Sendable {
    let rootURL: URL

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.rootURL = base
                .appendingPathComponent("TennisClips", isDirectory: true)
                .appendingPathComponent("Sessions", isDirectory: true)
        }
    }

    func prepareSession(_ id: UUID) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: sessionURL(id).appendingPathComponent("sources", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: sessionURL(id).appendingPathComponent("exports", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: sessionURL(id).appendingPathComponent("clips", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    func persist(_ movie: ImportedMovie, sessionID: UUID, order: Int) throws -> String {
        try prepareSession(sessionID)
        let ext = movie.url.pathExtension.isEmpty ? "mov" : movie.url.pathExtension
        let filename = "source-" + String(format: "%03d", order + 1) + "." + ext
        let relativePath = "sources/" + filename
        let destination = url(for: sessionID, relativePath: relativePath)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: movie.url, to: destination)
        } catch {
            try FileManager.default.copyItem(at: movie.url, to: destination)
            movie.removeLocalCopy()
        }
        return relativePath
    }

    func sessionURL(_ id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func url(for sessionID: UUID, relativePath: String) -> URL {
        sessionURL(sessionID).appendingPathComponent(relativePath)
    }

    func compilationRelativePath() -> String {
        "exports/compilation.mp4"
    }

    func clipRelativePath(_ clipID: UUID) -> String {
        "clips/\(clipID.uuidString).mp4"
    }

    func removeSession(_ id: UUID) {
        try? FileManager.default.removeItem(at: sessionURL(id))
    }
}
