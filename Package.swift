// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MicrophonePicker",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MicrophonePicker",
            path: "Sources/MicrophonePicker"
        )
    ]
)
