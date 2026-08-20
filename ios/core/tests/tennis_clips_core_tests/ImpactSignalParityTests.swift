import Foundation
import Testing
@testable import TennisClipsCore

@Test func signalDetectorMatchesSciPyReferenceFixture() {
    let sampleRate = 16_000
    let count = sampleRate * 12
    var samples = [Float](repeating: 0, count: count)
    let impacts: [(center: Double, amplitude: Double, frequency: Double)] = [
        (1.5, 0.65, 1_100),
        (3.25, 0.52, 1_450),
        (4.02, 0.70, 900),
        (7.4, 0.48, 1_300),
        (10.0, 0.80, 1_000),
    ]

    for index in 0..<count {
        let time = Double(index) / Double(sampleRate)
        var value = 0.002 * sin(2 * .pi * 173 * time)
            + 0.0015 * sin(2 * .pi * 911 * time)
            + 0.001 * sin(2 * .pi * 3_100 * time)
        for impact in impacts {
            let offset = time - impact.center
            if abs(offset) < 0.06 {
                value += impact.amplitude
                    * exp(-abs(offset) * 110)
                    * sin(2 * .pi * impact.frequency * offset)
            }
        }
        samples[index] = Float(value)
    }

    let candidates = ImpactSignalDetector().candidates(samples: samples)
    let scipyTimes = [1.5, 3.25, 4.02, 7.4, 10.0]

    #expect(candidates.count == scipyTimes.count)
    for (candidate, reference) in zip(candidates, scipyTimes) {
        #expect(abs(candidate.time - reference) <= 0.005)
    }
}

@Test func signalDetectorReportsMonotonicIntermediateProgress() {
    let samples = [Float](repeating: 0, count: 16_000)
    var updates: [Double] = []

    _ = ImpactSignalDetector().candidates(samples: samples) { fraction in
        updates.append(fraction)
    }

    #expect(updates.first == 0)
    #expect(updates.last == 1)
    #expect(updates == updates.sorted())
    #expect(updates.contains { 0.2 < $0 && $0 < 0.9 })
}
