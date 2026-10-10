// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "smart-work",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "smart-work", targets: ["SmartWorkCLI"]),
        .executable(name: "SmartWork", targets: ["SmartWorkApp"]),
        .executable(name: "smart-work-helper", targets: ["SmartWorkHelper"]),
    ],
    targets: [
        .target(name: "SmartWorkCore", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "SmartWorkCLI", dependencies: ["SmartWorkCore"]),
        .executableTarget(name: "SmartWorkApp", dependencies: ["SmartWorkCore"]),
        .executableTarget(name: "SmartWorkHelper", dependencies: ["SmartWorkCore"]),
        .testTarget(name: "SmartWorkCoreTests", dependencies: ["SmartWorkCore"]),
    ]
)
