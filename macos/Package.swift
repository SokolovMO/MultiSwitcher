// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MultiSwitcher",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "MultiSwitcherCore",
            path: "Sources/MultiSwitcherCore"
        ),
        .executableTarget(
            name: "MultiSwitcher",
            dependencies: ["MultiSwitcherCore"],
            path: "Sources/MultiSwitcher",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "MultiSwitcherCoreTests",
            dependencies: ["MultiSwitcherCore"],
            path: "Tests/MultiSwitcherCoreTests"
        ),
    ]
)
