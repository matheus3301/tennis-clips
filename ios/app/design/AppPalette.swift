import SwiftUI

enum AppPalette {
    static let baseline = Color(red: 0.08, green: 0.19, blue: 0.24)
    static let hardCourt = Color(red: 0.20, green: 0.46, blue: 0.55)
    static let courtMist = Color(red: 0.86, green: 0.91, blue: 0.89)
    static let chalk = Color(red: 0.96, green: 0.97, blue: 0.95)
    static let ball = Color(red: 0.84, green: 0.92, blue: 0.31)
    static let clayMark = Color(red: 0.85, green: 0.37, blue: 0.25)
    static let ink = Color(red: 0.06, green: 0.14, blue: 0.18)

    // Compatibility aliases while the remaining algorithm-only screens disappear.
    static let court = baseline
    static let courtBlue = hardCourt
    static let line = courtMist
    static let clay = clayMark
}
