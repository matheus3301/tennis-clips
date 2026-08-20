import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct ImportedMovie: Transferable {
    let url: URL
    let originalName: String

    init(url: URL, originalName: String? = nil) {
        self.url = url
        self.originalName = originalName ?? url.lastPathComponent
    }

    func removeLocalCopy() {
        try? FileManager.default.removeItem(at: url)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("imports", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return ImportedMovie(url: destination, originalName: received.file.lastPathComponent)
        }
    }
}
