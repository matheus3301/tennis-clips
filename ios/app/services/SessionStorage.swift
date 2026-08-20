import Foundation

nonisolated enum SessionStorageError: LocalizedError {
    case insufficientSpace(requiredBytes: Int64, availableBytes: Int64)

    var errorDescription: String? {
        switch self {
        case .insufficientSpace(let requiredBytes, let availableBytes):
            let required = ByteCountFormatter.string(fromByteCount: requiredBytes, countStyle: .file)
            let available = ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
            return "Espaço insuficiente. Libere cerca de \(required); há \(available) disponíveis."
        }
    }
}

nonisolated struct SessionStorage: Sendable {
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
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try excludeFromBackup(rootURL)
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
        try excludeFromBackup(sessionURL(id))
    }

    func validateCapacity(for movies: [ImportedMovie]) throws {
        let sourceBytes = try movies.reduce(into: Int64.zero) { total, movie in
            let values = try movie.url.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values.fileSize ?? 0)
        }
        let reserveBytes: Int64 = 500 * 1_024 * 1_024
        let requiredBytes = sourceBytes + reserveBytes
        let capacityURL = rootURL.deletingLastPathComponent()
        let values = try capacityURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let availableBytes = values.volumeAvailableCapacityForImportantUsage else { return }
        guard availableBytes >= requiredBytes else {
            throw SessionStorageError.insufficientSpace(
                requiredBytes: requiredBytes,
                availableBytes: availableBytes
            )
        }
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

    func removeFile(sessionID: UUID, relativePath: String) {
        try? FileManager.default.removeItem(at: url(for: sessionID, relativePath: relativePath))
    }

    func removeCompilation(sessionID: UUID) {
        removeFile(sessionID: sessionID, relativePath: compilationRelativePath())
    }

    func stageFileRemoval(sessionID: UUID, relativePath: String) throws -> URL? {
        let source = url(for: sessionID, relativePath: relativePath)
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        let stagingRoot = sessionURL(sessionID)
            .appendingPathComponent(".pending-file-deletion", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        try excludeFromBackup(stagingRoot)
        let destination = stagingRoot.appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: source, to: destination)
        return destination
    }

    func restoreStagedFileRemoval(
        _ stagedURL: URL,
        sessionID: UUID,
        relativePath: String
    ) throws {
        let destination = url(for: sessionID, relativePath: relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: stagedURL, to: destination)
    }

    func removeSession(_ id: UUID) {
        try? FileManager.default.removeItem(at: sessionURL(id))
    }

    func stageRemoval(_ id: UUID) throws -> URL? {
        let source = sessionURL(id)
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        let stagingRoot = rootURL.appendingPathComponent(".pending-deletion", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        try excludeFromBackup(stagingRoot)
        let destination = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.moveItem(at: source, to: destination)
        return destination
    }

    func restoreStagedRemoval(_ stagedURL: URL, sessionID: UUID) throws {
        let destination = sessionURL(sessionID)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: stagedURL, to: destination)
    }

    func finalizeStagedRemoval(_ stagedURL: URL?) {
        guard let stagedURL else { return }
        try? FileManager.default.removeItem(at: stagedURL)
    }

    func storageUsageBytes() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.fileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileAllocatedSizeKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileAllocatedSize ?? 0)
        }
        return total
    }

    private func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }
}
