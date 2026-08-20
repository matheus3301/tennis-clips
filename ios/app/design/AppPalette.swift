import SwiftUI

enum AppPalette {
    static let baseline = Color("Baseline")
    static let hardCourt = Color("HardCourt")
    static let courtMist = Color("CourtMist")
    static let chalk = Color("Chalk")
    static let ball = Color("Ball")
    static let clayMark = Color("ClayMark")
    static let ink = Color("Ink")

    // Compatibility aliases while the remaining algorithm-only screens disappear.
    static let court = baseline
    static let courtBlue = hardCourt
    static let line = courtMist
    static let clay = clayMark
}
