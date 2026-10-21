// swift-tools-version: 6.0
import PackageDescription
import Foundation

let crashReportingEnabled = ProcessInfo.processInfo.environment["MULTISWITCHER_ENABLE_CRASH_REPORTING"] == "1"
let updatesEnabled = ProcessInfo.processInfo.environment["MULTISWITCHER_ENABLE_UPDATES"] == "1"
var packageDependencies: [Package.Dependency] = []
var appDependencies: [Target.Dependency] = ["MultiSwitcherCore"]

if updatesEnabled {
    packageDependencies.append(
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0")
    )
    appDependencies.append(.product(name: "Sparkle", package: "Sparkle"))
}

if crashReportingEnabled {
    packageDependencies.append(
        .package(url: "https://github.com/getsentry/sentry-apple-binaries.git", exact: "9.29.0")
    )
    appDependencies.append(.product(name: "Sentry-Static", package: "sentry-apple-binaries"))
}

let package = Package(
    name: "MultiSwitcher",
    platforms: [.macOS(.v15)],
    dependencies: packageDependencies,
    targets: [
        .target(
            name: "MultiSwitcherCore",
            path: "Sources/MultiSwitcherCore"
        ),
        .executableTarget(
            name: "MultiSwitcher",
            dependencies: appDependencies,
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
