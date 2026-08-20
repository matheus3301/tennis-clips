@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

struct CompilationSegment: Sendable {
    let sourceURL: URL
    let start: TimeInterval
    let end: TimeInterval

    var duration: TimeInterval { end - start }
}

private struct SegmentDescriptor {
    let asset: AVURLAsset
    let videoTrack: AVAssetTrack
    let audioTrack: AVAssetTrack?
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform
    let frameRate: Float
    let range: CMTimeRange

    var orientedRect: CGRect {
        CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
            .standardized
    }
}

// AVAssetExportSession's legacy callback predates Swift concurrency. The box
// only bridges that callback; the session remains owned by RallyVideoEditor.
private final class ExportSessionBox: @unchecked Sendable {
    let value: AVAssetExportSession

    init(_ value: AVAssetExportSession) {
        self.value = value
    }
}

actor RallyVideoEditor {
    func export(
        segments: [CompilationSegment],
        to outputURL: URL,
        progress: (@MainActor @Sendable (Double) -> Void)? = nil
    ) async throws {
        guard !segments.isEmpty else { throw ProcessingError.noImpacts }
        let descriptors = try await loadDescriptors(for: segments)
        guard let first = descriptors.first else { throw ProcessingError.noVideo }
        await progress?(0.04)

        let renderSize = Self.evenSize(first.orientedRect.size)
        let composition = AVMutableComposition()
        guard let compositionVideo = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw ProcessingError.cannotCreateExport }
        let compositionAudio = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var cursor = CMTime.zero
        var instructions: [AVMutableVideoCompositionInstruction] = []
        for descriptor in descriptors {
            try Task.checkCancellation()
            try compositionVideo.insertTimeRange(descriptor.range, of: descriptor.videoTrack, at: cursor)
            if let sourceAudio = descriptor.audioTrack, let compositionAudio {
                try compositionAudio.insertTimeRange(descriptor.range, of: sourceAudio, at: cursor)
            }

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: descriptor.range.duration)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideo)
            layer.setTransform(Self.fittedTransform(for: descriptor, renderSize: renderSize), at: cursor)
            instruction.layerInstructions = [layer]
            instructions.append(instruction)
            cursor = cursor + descriptor.range.duration
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = instructions
        videoComposition.renderSize = renderSize
        let maximumFrameRate = descriptors.map { $0.frameRate }.max() ?? 30
        videoComposition.frameDuration = CMTime(
            value: 1,
            timescale: CMTimeScale(max(24, min(maximumFrameRate, 60)))
        )

        try? FileManager.default.removeItem(at: outputURL)
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else { throw ProcessingError.cannotCreateExport }
        exporter.videoComposition = videoComposition
        let exporterBox = ExportSessionBox(exporter)
        let progressTask = Task {
            while !Task.isCancelled {
                await progress?(Double(exporterBox.value.progress))
                try? await Task.sleep(for: .milliseconds(180))
            }
        }
        defer { progressTask.cancel() }

        do {
            if #available(iOS 18.0, *) {
                try await exporter.export(to: outputURL, as: .mp4)
            } else {
                try await exportLegacy(exporter, to: outputURL)
            }
        } catch is CancellationError {
            exporter.cancelExport()
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw ProcessingError.exportFailed(error)
        }
        await progress?(1)
    }

    func export(segment: CompilationSegment, to outputURL: URL) async throws {
        try await export(segments: [segment], to: outputURL)
    }

    private func loadDescriptors(for segments: [CompilationSegment]) async throws -> [SegmentDescriptor] {
        var descriptors: [SegmentDescriptor] = []
        descriptors.reserveCapacity(segments.count)
        for segment in segments {
            let asset = AVURLAsset(url: segment.sourceURL)
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw ProcessingError.noVideo
            }
            let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let frameRate = try await videoTrack.load(.nominalFrameRate)
            let assetDuration = try await asset.load(.duration).seconds
            let start = max(0, segment.start)
            let end = min(assetDuration, segment.end)
            guard end > start else { continue }
            descriptors.append(SegmentDescriptor(
                asset: asset,
                videoTrack: videoTrack,
                audioTrack: audioTrack,
                naturalSize: naturalSize,
                preferredTransform: preferredTransform,
                frameRate: frameRate,
                range: CMTimeRange(
                    start: CMTime(seconds: start, preferredTimescale: 600),
                    duration: CMTime(seconds: end - start, preferredTimescale: 600)
                )
            ))
        }
        return descriptors
    }

    private static func fittedTransform(
        for descriptor: SegmentDescriptor,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let rect = descriptor.orientedRect
        let scale = min(renderSize.width / rect.width, renderSize.height / rect.height)
        let scaledSize = CGSize(width: rect.width * scale, height: rect.height * scale)
        let x = (renderSize.width - scaledSize.width) / 2
        let y = (renderSize.height - scaledSize.height) / 2

        return descriptor.preferredTransform
            .concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: x, y: y))
    }

    private static func evenSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(2, floor(size.width / 2) * 2),
            height: max(2, floor(size.height / 2) * 2)
        )
    }

    private func exportLegacy(_ exporter: AVAssetExportSession, to outputURL: URL) async throws {
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        let exporterBox = ExportSessionBox(exporter)
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            exporterBox.value.exportAsynchronously {
                switch exporterBox.value.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    continuation.resume(
                        throwing: exporterBox.value.error ?? ProcessingError.exportFailed(nil)
                    )
                }
            }
        }
    }
}
