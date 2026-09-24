// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Snipbook",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.2.1")
    ],
    targets: [
        .executableTarget(
            name: "Snipbook",
            dependencies: ["Highlightr"],
            path: "Sources/Snipbook",
            resources: [.copy("Resources/AppIcons")]
        ),
        .testTarget(
            name: "SnipbookTests",
            dependencies: ["Snipbook"],
            path: "Tests/SnipbookTests"
        )
    ]
)
