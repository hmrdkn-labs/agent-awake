// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "smart-work",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "smart-work", targets: ["SmartWorkCLI"]),
        .executable(name: "SmartWork", targets: ["SmartWorkApp"]),
    ],
    targets: [
        .target(name: "SmartWorkCore", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "SmartWorkCLI", dependencies: ["SmartWorkCore"]),
        .executableTarget(name: "SmartWorkApp", dependencies: ["SmartWorkCore"]),
        .testTarget(name: "SmartWorkCoreTests", dependencies: ["SmartWorkCore"]),
    ]
)
