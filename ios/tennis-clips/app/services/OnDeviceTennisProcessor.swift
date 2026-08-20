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

        let impacts = try await detector.detect(in: asset) { fraction in
            await progress(ProcessingUpdate(stage: .findingImpacts, fraction: fraction * 0.68))
        }
        guard !impacts.isEmpty else { throw ProcessingError.noImpacts }

        await progress(ProcessingUpdate(stage: .assemblingRallies, fraction: 0.74))
        let clips = planner.ranges(for: impacts, assetDuration: duration)
        let destination = Self.outputURL()

        await progress(ProcessingUpdate(stage: .exporting, fraction: 0.82))
        try await editor.export(asset: asset, clips: clips, to: destination)
        await progress(ProcessingUpdate(stage: .exporting, fraction: 1))

        return TrainingSession(
            sourceURL: url,
            outputURL: destination,
            impacts: impacts,
            clips: clips
        )
    }

    private static func outputURL() -> URL {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("compilacoes", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("treino-\(UUID().uuidString).mp4")
    }
}
