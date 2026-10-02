// swift-tools-version: 5.10

import PackageDescription

// The Parakeet helper lives in a package of its own so the application, its core library
// and its checks stay free of third-party code. Only this binary links FluidAudio.
let package = Package(
    name: "VoiceFlowParakeet",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.4"),
    ],
    targets: [
        .executableTarget(
            name: "VoiceFlowParakeet",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        ),
    ]
)
