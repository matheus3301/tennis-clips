@preconcurrency import AVFoundation
import Foundation

nonisolated enum MediaPreflightError: LocalizedError {
    case missingVideo(String)
    case missingAudio(String)
    case videoTooLong(String, minutes: Int)

    var errorDescription: String? {
        switch self {
        case .missingVideo(let name):
            "\(name) não contém uma faixa de vídeo utilizável."
        case .missingAudio(let name):
            "\(name) não contém áudio. Escolha uma gravação com o som da quadra."
        case .videoTooLong(let name, let minutes):
            "\(name) tem mais de \(minutes) minutos. Divida a gravação em partes menores antes de importar."
        }
    }
}

nonisolated struct MediaPreflightService: Sendable {
    private let maximumDuration: TimeInterval = 30 * 60
    private let metadataService = MediaMetadataService()

    func validate(_ movies: [ImportedMovie]) async throws -> [ImportedMovieMetadata] {
        var results: [ImportedMovieMetadata] = []
        results.reserveCapacity(movies.count)
        for movie in movies {
            let asset = AVURLAsset(url: movie.url)
            guard try await !asset.loadTracks(withMediaType: .video).isEmpty else {
                throw MediaPreflightError.missingVideo(movie.originalName)
            }
            guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
                throw MediaPreflightError.missingAudio(movie.originalName)
            }
            let metadata = try await metadataService.metadata(for: movie, asset: asset)
            let duration = metadata.duration
            guard duration.isFinite, duration > 0 else {
                throw ProcessingError.cannotReadMedia
            }
            guard duration <= maximumDuration else {
                throw MediaPreflightError.videoTooLong(movie.originalName, minutes: 30)
            }
            results.append(metadata)
        }
        return results
    }
}
