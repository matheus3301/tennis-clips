@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

actor SessionVisualContextProvider {
    func frames(for requests: [SessionVisualFrameRequest]) async -> [CGImage] {
        var frames: [CGImage] = []
        frames.reserveCapacity(min(requests.count, 3))
        for request in requests.prefix(3) {
            guard !Task.isCancelled else { return frames }
            let asset = AVURLAsset(url: request.videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1_024, height: 1_024)
            let time = CMTime(seconds: max(0, request.time), preferredTimescale: 600)
            if let result = try? await generator.image(at: time) {
                frames.append(result.image)
            }
        }
        return frames
    }
}
