@preconcurrency import AVFoundation
import Accelerate
import CoreMedia
import Foundation
import TennisClipsCore

actor ImpactDetector {
    private struct Feature {
        let time: TimeInterval
        let amplitude: Float
        let midRatio: Float
        let highRatio: Float
    }

    private let sampleRate = 16_000.0
    private let windowSize = 1_024
    private let hopSize = 320
    private let amplitudePercentile = 0.985
    private let minimumEventDistance = 0.7

    func detect(
        in asset: AVAsset,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> [ImpactEvent] {
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
        samples.reserveCapacity(windowSize * 4)
        var cursor = 0
        var processedSamples = 0
        var features: [Feature] = []
        let window = (0..<windowSize).map { index in
            Float(0.5 - 0.5 * cos(2 * .pi * Double(index) / Double(windowSize - 1)))
        }
        let dft = try vDSP.DiscreteFourierTransform(
            count: windowSize,
            direction: .forward,
            transformType: .complexComplex,
            ofType: Float.self
        )

        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            samples.append(contentsOf: Self.floatSamples(from: sampleBuffer))
            while samples.count - cursor >= windowSize {
                let slice = Array(samples[cursor..<(cursor + windowSize)])
                features.append(Self.feature(
                    samples: slice,
                    window: window,
                    dft: dft,
                    time: Double(processedSamples) / sampleRate,
                    sampleRate: sampleRate
                ))
                cursor += hopSize
                processedSamples += hopSize
            }
            if cursor > windowSize * 8 {
                samples.removeFirst(cursor)
                cursor = 0
            }
            await progress(min(0.96, Double(processedSamples) / max(duration * sampleRate, 1)))
        }
        if reader.status == .failed { throw reader.error ?? ProcessingError.cannotReadMedia }
        return candidates(from: features)
    }

    private func candidates(from features: [Feature]) -> [ImpactEvent] {
        guard features.count >= 3 else { return [] }
        let ordered = features.map(\.amplitude).sorted()
        let thresholdIndex = min(ordered.count - 1, Int(Double(ordered.count - 1) * amplitudePercentile))
        let threshold = max(ordered[thresholdIndex], 0.000_001)
        var events: [ImpactEvent] = []

        for index in 1..<(features.count - 1) {
            let value = features[index]
            guard value.amplitude >= threshold,
                  value.amplitude > features[index - 1].amplitude,
                  value.amplitude >= features[index + 1].amplitude,
                  value.midRatio >= 0.07,
                  value.highRatio <= 0.35,
                  value.time - (events.last?.time ?? -.infinity) >= minimumEventDistance
            else { continue }

            let amplitudeScore = Double(value.amplitude / threshold)
            let spectralScore = min(2, Double(value.midRatio / 0.15))
            events.append(ImpactEvent(
                time: value.time,
                score: amplitudeScore * (0.6 + 0.4 * spectralScore),
                amplitude: Double(value.amplitude),
                midEnergyRatio: Double(value.midRatio),
                highEnergyRatio: Double(value.highRatio)
            ))
        }
        return events
    }

    private static func feature(
        samples: [Float],
        window: [Float],
        dft: vDSP.DiscreteFourierTransform<Float>,
        time: TimeInterval,
        sampleRate: Double
    ) -> Feature {
        let windowed = vDSP.multiply(samples, window)
        let imaginary = [Float](repeating: 0, count: windowed.count)
        var realOutput = imaginary
        var imaginaryOutput = imaginary
        dft.transform(
            inputReal: windowed,
            inputImaginary: imaginary,
            outputReal: &realOutput,
            outputImaginary: &imaginaryOutput
        )
        let powers = zip(realOutput, imaginaryOutput).map { $0 * $0 + $1 * $1 }
        let nyquistCount = powers.count / 2
        let binWidth = sampleRate / Double(windowed.count)

        func energy(from lower: Double, to upper: Double) -> Float {
            let start = max(0, Int(lower / binWidth))
            let end = min(nyquistCount, Int(upper / binWidth))
            guard end > start else { return 0 }
            return powers[start..<end].reduce(0, +)
        }

        let full = max(energy(from: 80, to: 7_500), 0.000_000_001)
        return Feature(
            time: time,
            amplitude: vDSP.rootMeanSquare(samples),
            midRatio: energy(from: 600, to: 4_800) / full,
            highRatio: energy(from: 1_800, to: 7_500) / full
        )
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
            Float(Int16(littleEndian: values[$0])) / Float(Int16.max)
        }
    }
}
