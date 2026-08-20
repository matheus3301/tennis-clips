@preconcurrency import AVFoundation
import CoreLocation
import Foundation
import Photos

nonisolated struct MediaMetadataService: Sendable {
    func metadata(
        for movie: ImportedMovie,
        asset suppliedAsset: AVURLAsset? = nil
    ) async throws -> ImportedMovieMetadata {
        let asset = suppliedAsset ?? AVURLAsset(url: movie.url)
        let duration = try await asset.load(.duration).seconds
        let metadata = try await asset.load(.metadata)
        let fileDate = await Self.creationDate(in: metadata)
        let fileCoordinate = await Self.coordinate(in: metadata)
        let photoMetadata = photoLibraryMetadata(for: movie.assetIdentifier)

        return ImportedMovieMetadata(
            duration: duration.isFinite ? duration : 0,
            capturedAt: photoMetadata.capturedAt ?? fileDate,
            latitude: photoMetadata.latitude ?? fileCoordinate?.latitude,
            longitude: photoMetadata.longitude ?? fileCoordinate?.longitude
        )
    }

    static func creationDate(in metadata: [AVMetadataItem]) async -> Date? {
        guard let item = metadata.first(where: {
            $0.identifier == .commonIdentifierCreationDate
                || $0.identifier == .quickTimeMetadataCreationDate
        }), let value = try? await item.load(.stringValue) else {
            return nil
        }
        return try? Date(value, strategy: .iso8601)
    }

    static func coordinate(in metadata: [AVMetadataItem]) async -> CLLocationCoordinate2D? {
        guard let item = metadata.first(where: {
            $0.identifier == .quickTimeMetadataLocationISO6709
                || $0.identifier == .commonIdentifierLocation
        }), let value = try? await item.load(.stringValue) else {
            return nil
        }
        return Self.parseISO6709(value)
    }

    private func photoLibraryMetadata(for identifier: String?) -> ImportedMovieMetadata {
        guard let identifier else { return .empty }
        let authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard authorization == .authorized || authorization == .limited,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
        else {
            return .empty
        }
        return ImportedMovieMetadata(
            duration: asset.duration,
            capturedAt: asset.creationDate,
            latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude
        )
    }

    static func parseISO6709(_ value: String) -> CLLocationCoordinate2D? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.first == "+" || text.first == "-" else { return nil }
        let signs = text.indices.dropFirst().filter { text[$0] == "+" || text[$0] == "-" }
        guard let longitudeStart = signs.first else { return nil }
        let longitudeEnd = signs.dropFirst().first ?? text.firstIndex(of: "/") ?? text.endIndex
        guard let latitude = Double(text[..<longitudeStart]),
              let longitude = Double(text[longitudeStart..<longitudeEnd]),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude)
        else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
