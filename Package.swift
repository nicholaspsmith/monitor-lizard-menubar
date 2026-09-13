// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MonitorLizard",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MonitorLizard", targets: ["MonitorLizard"]),
        .library(name: "MonitorLizardCore", targets: ["MonitorLizardCore"]),
    ],
    dependencies: [
        .package(path: "../StatusItemKit"),
    ],
    targets: [
        .target(name: "MonitorLizardCore"),
        .executableTarget(
            name: "MonitorLizard",
            dependencies: ["MonitorLizardCore", .product(name: "StatusItemKit", package: "StatusItemKit")]
        ),
        .testTarget(name: "MonitorLizardCoreTests", dependencies: ["MonitorLizardCore"]),
    ]
)
