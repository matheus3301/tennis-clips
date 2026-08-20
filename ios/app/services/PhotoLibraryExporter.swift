import Foundation
import Photos

nonisolated enum PhotoLibraryExportError: LocalizedError {
    case accessDenied

    var errorDescription: String? {
        "Ative o acesso para adicionar vídeos em Ajustes e tente novamente."
    }
}

struct PhotoLibraryExporter: Sendable {
    func saveVideo(at url: URL) async throws {
        let status = await authorizationStatus()
        guard status == .authorized || status == .limited else {
            throw PhotoLibraryExportError.accessDenied
        }
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? PhotoLibraryExportError.accessDenied)
                }
            }
        }
    }

    private func authorizationStatus() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
