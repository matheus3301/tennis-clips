import Foundation
import Photos

nonisolated enum PhotoLibraryExportError: LocalizedError {
    case accessDenied

    var errorDescription: String? {
        "Ative o acesso para adicionar vídeos em Ajustes e tente novamente."
    }
}

nonisolated struct PhotoLibraryExporter: Sendable {
    func saveVideo(at url: URL) async throws {
        let status = await authorizationStatus()
        guard status == .authorized || status == .limited else {
            throw PhotoLibraryExportError.accessDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    private func authorizationStatus() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }
        return await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    }
}
