import ActivityKit
import Foundation

struct TennisProcessingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var progress: Double
        var stage: String
        var currentVideo: Int
        var totalVideos: Int
    }

    let sessionID: String
    let title: String
}
