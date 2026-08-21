import Foundation

nonisolated struct ImportedMovieMetadata: Sendable, Equatable {
    let duration: TimeInterval
    let capturedAt: Date?
    let latitude: Double?
    let longitude: Double?

    static let empty = ImportedMovieMetadata(
        duration: 0,
        capturedAt: nil,
        latitude: nil,
        longitude: nil
    )
}
