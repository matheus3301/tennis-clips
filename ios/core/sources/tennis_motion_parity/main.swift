@preconcurrency import AVFoundation
import Foundation
import TennisClipsCore

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: tennis-motion-parity <video> <candidate-times-json>\n".utf8))
    exit(2)
}

let videoURL = URL(fileURLWithPath: CommandLine.arguments[1])
let timesArgument = CommandLine.arguments[2]
let timesData = if timesArgument.hasPrefix("[") {
    Data(timesArgument.utf8)
} else {
    try Data(contentsOf: URL(fileURLWithPath: timesArgument))
}
let times = try JSONDecoder().decode([Double].self, from: timesData)
let asset = AVURLAsset(url: videoURL)
let validator = MotionValidator()
var results: [[String: Double]] = []
results.reserveCapacity(times.count)

for time in times {
    let measurement = try validator.measurement(in: asset, at: time, offset: 0.05)
    results.append([
        "time": time,
        "motion_ratio": measurement.ratio,
        "roi_min_x": Double(measurement.minX),
        "roi_min_y": Double(measurement.minY),
        "roi_max_x": Double(measurement.maxX),
        "roi_max_y": Double(measurement.maxY),
    ])
}

let output = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(output)
FileHandle.standardOutput.write(Data("\n".utf8))
