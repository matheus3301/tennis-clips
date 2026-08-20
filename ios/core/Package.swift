// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TennisClipsCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "TennisClipsCore", targets: ["TennisClipsCore"]),
        .executable(name: "tennis-signal-parity", targets: ["TennisSignalParity"]),
        .executable(name: "tennis-motion-parity", targets: ["TennisMotionParity"]),
    ],
    targets: [
        .target(name: "TennisClipsCore", path: "sources/tennis_clips_core"),
        .executableTarget(
            name: "TennisSignalParity",
            dependencies: ["TennisClipsCore"],
            path: "sources/tennis_signal_parity"
        ),
        .executableTarget(
            name: "TennisMotionParity",
            dependencies: ["TennisClipsCore"],
            path: "sources/tennis_motion_parity"
        ),
        .testTarget(
            name: "TennisClipsCoreTests",
            dependencies: ["TennisClipsCore"],
            path: "tests/tennis_clips_core_tests"
        ),
    ]
)
