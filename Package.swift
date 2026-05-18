// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TaurusRecorder",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TaurusRecorder", targets: ["TaurusRecorder"]),
        .library(name: "TaurusRecorderCore", targets: ["TaurusRecorderCore"])
    ],
    targets: [
        .target(
            name: "TaurusRecorderCore",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "TaurusRecorder",
            dependencies: ["TaurusRecorderCore"],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation")
            ]
        ),
        .executableTarget(
            name: "CoreBehaviorTests",
            dependencies: ["TaurusRecorderCore"],
            path: "Tests/CoreBehaviorTests",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        )
    ]
)
