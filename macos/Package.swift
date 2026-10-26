// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "SanbluedotVoiceFlowMac",
    // 14: the Parakeet helper needs it, and the app offered Parakeet on 13 (D-86).
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VoiceFlowMac", targets: ["VoiceFlowMac"]),
        // Offered to the outside so an Xcode target can link it. The target already
        // existed; without a product it was reachable only from inside this package,
        // and an App Intent declared here needs the library to be linkable.
        .library(name: "VoiceFlowMacCore", targets: ["VoiceFlowMacCore"]),
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
        // The Python engine reaches Apple's on-device model by running this, the same
        // way it reaches whisper.cpp. It depends on nothing in the application, so the
        // cleanup step stays in the engine and keeps facing the output guard.
        .executableTarget(name: "VoiceFlowAppleCleaner"),
    ]
)
