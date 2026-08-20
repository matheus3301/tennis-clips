import Foundation
import TennisClipsCore

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: tennis-signal-parity <mono-f32le>\n".utf8))
    exit(2)
}

let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
guard data.count.isMultiple(of: MemoryLayout<UInt32>.size) else {
    FileHandle.standardError.write(Data("input must contain little-endian Float32 samples\n".utf8))
    exit(2)
}

let samples = data.withUnsafeBytes { bytes -> [Float] in
    var result: [Float] = []
    result.reserveCapacity(data.count / MemoryLayout<UInt32>.size)
    for offset in stride(from: 0, to: data.count, by: MemoryLayout<UInt32>.size) {
        let bits = UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        result.append(Float(bitPattern: bits))
    }
    return result
}

let candidates = ImpactSignalDetector().candidates(samples: samples)
let payload: [[String: Double]] = candidates.map { candidate in
    [
        "time": candidate.time,
        "amplitude": candidate.amplitude,
        "threshold": candidate.threshold,
        "mid_energy_ratio": candidate.midEnergyRatio,
        "high_energy_ratio": candidate.highEnergyRatio,
    ]
}
let output = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(output)
FileHandle.standardOutput.write(Data("\n".utf8))
