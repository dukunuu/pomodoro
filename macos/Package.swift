// swift-tools-version: 6.0
import PackageDescription

// The native macOS front end is a SwiftPM executable rather than an Xcode
// project so it builds from the command line with only the Command Line
// Tools installed. build-macos.sh wraps the binary in a real .app bundle.
let package = Package(
    name: "Pomodoro",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Pomodoro",
            path: "Sources/Pomodoro",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
