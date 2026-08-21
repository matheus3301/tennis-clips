import Foundation

nonisolated struct SessionVisualFrameRequest: Sendable {
    let videoURL: URL
    let time: TimeInterval
}
