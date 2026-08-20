@preconcurrency import AVFoundation
import Foundation
import TennisClipsCore

actor OnDeviceTennisProcessor: TennisAnalyzing {
    private let detector = ImpactDetector()
    private let planner = ClipPlanner()

    func analyze(
        videoAt url: URL,
        progress: @escaping @MainActor @Sendable (ProcessingUpdate) -> Void
    ) async throws -> VideoAnalysis {
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
        await progress(ProcessingUpdate(stage: .assemblingRallies, fraction: 1))

        return VideoAnalysis(
            duration: duration,
            impacts: impacts,
            clips: clips
        )
    }
}
