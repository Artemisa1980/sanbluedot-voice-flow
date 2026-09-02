// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "SanbluedotVoiceFlowMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "VoiceFlowMac", targets: ["VoiceFlowMac"]),
    ],
    targets: [
        .target(name: "VoiceFlowMacCore"),
        .executableTarget(
            name: "VoiceFlowMac",
            dependencies: ["VoiceFlowMacCore"]
        ),
        .executableTarget(
            name: "VoiceFlowMacCoreChecks",
            dependencies: ["VoiceFlowMacCore"]
        ),
    ]
)
