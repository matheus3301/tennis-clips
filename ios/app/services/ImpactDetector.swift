@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import TennisClipsCore

actor ImpactDetector {
    private let sampleRate = 16_000.0
    private let minimumMotionRatio = 0.08
    private let signalDetector = ImpactSignalDetector()

    func detect(
        in asset: AVAsset,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> [ImpactEvent] {
        let samples = try await readSamples(from: asset) { fraction in
            await progress(fraction * 0.18)
        }

        await progress(0.2)
        let detector = signalDetector
        let (progressUpdates, progressContinuation) = AsyncStream.makeStream(
            of: Double.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let candidateTask = Task.detached(priority: .userInitiated) {
            defer { progressContinuation.finish() }
            return detector.candidates(samples: samples) { fraction in
                progressContinuation.yield(fraction)
            }
        }
        defer { candidateTask.cancel() }
        for await fraction in progressUpdates {
            try Task.checkCancellation()
            await progress(0.2 + fraction * 0.44)
        }
        let candidates = await candidateTask.value
        await progress(0.64)

        let motionSession = MotionValidationSession(asset: asset)
        var events: [ImpactEvent] = []
        var lastReportedVisualProgress = 0.64
        events.reserveCapacity(candidates.count)
        for (index, candidate) in candidates.enumerated() {
            try Task.checkCancellation()
            // Missing edge frames are rejected, matching the Python detector.
            let movement = (try? await motionSession.motionRatio(
                at: candidate.time,
                offset: 0.05
            )) ?? 0
            if movement >= minimumMotionRatio {
                let amplitudeScore = candidate.amplitude / candidate.threshold
                let spectralScore = min(2, candidate.midEnergyRatio / 0.15)
                let motionScore = min(2, movement / minimumMotionRatio)
                let score = amplitudeScore * (0.5 + 0.25 * spectralScore + 0.25 * motionScore)
                events.append(ImpactEvent(
                    time: candidate.time,
                    score: score,
                    amplitude: candidate.amplitude,
                    midEnergyRatio: candidate.midEnergyRatio,
                    highEnergyRatio: candidate.highEnergyRatio,
                    motionRatio: movement
                ))
            }
            let visualFraction = Double(index + 1) / Double(max(candidates.count, 1))
            let overallProgress = 0.64 + visualFraction * 0.36
            if overallProgress >= 1 || overallProgress - lastReportedVisualProgress >= 0.015 {
                lastReportedVisualProgress = overallProgress
                await progress(overallProgress)
            }
        }
        return events
    }

    private func readSamples(
        from asset: AVAsset,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> [Float] {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw ProcessingError.noAudio }
        let duration = try await asset.load(.duration).seconds
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ProcessingError.cannotReadMedia }
        reader.add(output)
        guard reader.startReading() else { throw ProcessingError.cannotReadMedia }

        var samples: [Float] = []
        var lastReportedProgress = 0.0
        samples.reserveCapacity(Int(max(duration * sampleRate, sampleRate)))
        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            samples.append(contentsOf: Self.floatSamples(from: sampleBuffer))
            let currentProgress = min(1, Double(samples.count) / max(duration * sampleRate, 1))
            if currentProgress >= 1 || currentProgress - lastReportedProgress >= 0.015 {
                lastReportedProgress = currentProgress
                await progress(currentProgress)
            }
        }
        if reader.status == .failed { throw reader.error ?? ProcessingError.cannotReadMedia }
        return samples
    }

    private static func floatSamples(from sampleBuffer: CMSampleBuffer) -> [Float] {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return [] }
        var totalLength = 0
        var pointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            block,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &pointer
        )
        guard status == kCMBlockBufferNoErr, let pointer else { return [] }
        let values = UnsafeRawPointer(pointer).assumingMemoryBound(to: Int16.self)
        return (0..<(totalLength / MemoryLayout<Int16>.size)).map {
            Float(Int16(littleEndian: values[$0])) / 32_768
        }
    }
}
