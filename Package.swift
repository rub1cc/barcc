// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "barcc",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "barcc",
            path: "Sources/ClaudeUsage",
            resources: [
                .copy("../../Resources/Info.plist")
            ]
        )
    ]
)
