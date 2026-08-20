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
    ],
    targets: [
        .target(name: "TennisClipsCore", path: "sources/tennis_clips_core"),
        .testTarget(
            name: "TennisClipsCoreTests",
            dependencies: ["TennisClipsCore"],
            path: "tests/tennis_clips_core_tests"
        ),
    ]
)
