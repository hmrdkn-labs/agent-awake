// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "agent-awake",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "agentawake", targets: ["AgentAwakeCLI"]),
        .executable(name: "AgentAwakeApp", targets: ["AgentAwakeApp"]),
        .executable(name: "agentawake-helper", targets: ["AgentAwakeHelper"]),
    ],
    targets: [
        .target(name: "AgentAwakeCore", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "AgentAwakeCLI", dependencies: ["AgentAwakeCore"]),
        .executableTarget(name: "AgentAwakeApp", dependencies: ["AgentAwakeCore"]),
        .executableTarget(name: "AgentAwakeHelper", dependencies: ["AgentAwakeCore"]),
        .testTarget(name: "AgentAwakeCoreTests", dependencies: ["AgentAwakeCore"]),
    ]
)
