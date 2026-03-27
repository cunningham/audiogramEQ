// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudiogramEQ",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "AudiogramEQ",
            path: "AudiogramEQ",
            exclude: [
                "Resources/Assets.xcassets",
                "Preview Content",
                "AudiogramEQ.entitlements"
            ]
        )
    ]
)
