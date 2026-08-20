// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SubmissionTracker",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "SubmissionTrackerCore", targets: ["SubmissionTrackerCore"]),
        .executable(name: "SubmissionTracker", targets: ["SubmissionTrackerApp"]),
    ],
    targets: [
        .target(
            name: "SubmissionTrackerCore",
            path: "Sources/SubmissionTrackerCore"
        ),
        .executableTarget(
            name: "SubmissionTrackerApp",
            dependencies: ["SubmissionTrackerCore"],
            path: "Sources/SubmissionTrackerApp",
            exclude: ["Info.plist"],
            resources: [.process("Resources")]
        ),
    ]
)
