@preconcurrency import AVFoundation
import Foundation
import TennisClipsCore

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

actor RallyVideoEditor {
    func export(asset: AVAsset, clips: [ClipRange], to outputURL: URL) async throws {
        let sourceVideoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideo = sourceVideoTracks.first else { throw ProcessingError.noVideo }
        let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw ProcessingError.cannotCreateExport }
        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)

        var cursor = CMTime.zero
        for clip in clips {
            let range = CMTimeRange(
                start: CMTime(seconds: clip.start, preferredTimescale: 600),
                duration: CMTime(seconds: clip.duration, preferredTimescale: 600)
            )
            try videoTrack.insertTimeRange(range, of: sourceVideo, at: cursor)
            if let sourceAudio, let audioTrack {
                try audioTrack.insertTimeRange(range, of: sourceAudio, at: cursor)
            }
            cursor = cursor + range.duration
        }

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else { throw ProcessingError.cannotCreateExport }
        if #available(iOS 18.0, macOS 15.0, *) {
            do {
                try await exporter.export(to: outputURL, as: .mp4)
            } catch {
                throw ProcessingError.exportFailed(error)
            }
        } else {
            exporter.outputURL = outputURL
            exporter.outputFileType = .mp4
            let box = ExportSessionBox(exporter)
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                exporter.exportAsynchronously {
                    switch box.session.status {
                    case .completed:
                        continuation.resume()
                    case .failed, .cancelled:
                        continuation.resume(
                            throwing: ProcessingError.exportFailed(box.session.error)
                        )
                    default:
                        continuation.resume(
                            throwing: ProcessingError.exportFailed(box.session.error)
                        )
                    }
                }
            }
        }
    }
}
