// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YTBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "YTBar",
            path: "Sources",
            resources: [
                .copy("Resources/setup-guide.html"),
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Security"),
                .linkedFramework("MediaPlayer"),
            ]
        ),
        .testTarget(
            name: "YTBarTests",
            dependencies: ["YTBar"],
            path: "Tests"
        ),
    ]
)
