import ActivityKit
import Foundation

nonisolated struct TennisProcessingAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var progress: Double
        var stage: String
        var currentVideo: Int
        var totalVideos: Int
    }

    let sessionID: String
    let title: String

    var deepLinkURL: URL? {
        URL(string: "tennisclips://session/\(sessionID)")
    }
}
