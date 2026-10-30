// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexEyes",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexEyes", targets: ["CodexEyes"]),
        .executable(name: "CodexEyesHook", targets: ["CodexEyesHook"])
    ],
    targets: [
        .target(name: "CodexEyesCore", resources: [.process("Resources")]),
        .executableTarget(name: "CodexEyes", dependencies: ["CodexEyesCore"]),
        .executableTarget(name: "CodexEyesHook", dependencies: ["CodexEyesCore"]),
        .testTarget(name: "CodexEyesCoreTests", dependencies: ["CodexEyesCore"]),
        .testTarget(name: "CodexEyesUITests", dependencies: ["CodexEyes"])
    ]
)
