@preconcurrency import AVFoundation
import Foundation
import TennisClipsCore

actor OnDeviceTennisProcessor: TennisProcessing {
    private let detector = ImpactDetector()
    private let editor = RallyVideoEditor()
    private let planner = ClipPlanner()

    func process(
        videoAt url: URL,
        progress: @escaping @MainActor @Sendable (ProcessingUpdate) -> Void
    ) async throws -> TrainingSession {
        await progress(ProcessingUpdate(stage: .readingAudio, fraction: 0.05))
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw ProcessingError.cannotReadMedia }

        let impacts = try await detector.detect(in: asset) { fraction in
            await progress(ProcessingUpdate(stage: .findingImpacts, fraction: fraction * 0.68))
        }
        guard !impacts.isEmpty else { throw ProcessingError.noImpacts }

        await progress(ProcessingUpdate(stage: .assemblingRallies, fraction: 0.74))
        let clips = planner.ranges(for: impacts, assetDuration: duration)
        let destination = try Self.makeOutputURL()

        await progress(ProcessingUpdate(stage: .exporting, fraction: 0.82))
        do {
            try await editor.export(asset: asset, clips: clips, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        await progress(ProcessingUpdate(stage: .exporting, fraction: 1))

        return TrainingSession(
            outputURL: destination,
            impacts: impacts,
            clips: clips
        )
    }

    private static func makeOutputURL() throws -> URL {
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory
            .appendingPathComponent("exports", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        if let staleExports = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        ) {
            for staleExport in staleExports where staleExport.pathExtension.lowercased() == "mp4" {
                try? fileManager.removeItem(at: staleExport)
            }
        }
        return folder.appendingPathComponent("treino-\(UUID().uuidString).mp4")
    }
}
