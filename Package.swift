// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MultiAudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MultiAudio", targets: ["MultiAudio"])
    ],
    targets: [
        .executableTarget(
            name: "MultiAudio",
            path: "Sources/MultiAudio",
            exclude: [
                "Resources/Info.plist"
            ],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement")
            ]
        )
        // Unit tests require full Xcode (XCTest). Enable when Xcode is installed:
        // .testTarget(name: "MultiAudioTests", path: "Tests/MultiAudioTests")
    ]
)
