// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MetricsKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        // UI-independent core: providers, scheduler, store, and engine.
        .library(name: "MetricsKit", targets: ["MetricsKit"]),
        // Read-only automation interface shipped inside Macnitor.app.
        .executable(name: "macnitor", targets: ["MacnitorCLI"]),
        // Internal provider readout for development and hardware validation.
        .executable(name: "metricskit-demo", targets: ["MetricsKitDemo"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            exact: "1.8.2"
        )
    ],
    targets: [
        // The whole package builds in the Swift 6 language mode: providers wrap C-based
        // Mach/IOKit state in `@unchecked Sendable` types that own their own queue or
        // lock, so strict concurrency checks the boundaries we actually cross.
        .target(name: "MetricsKit"),
        .target(
            name: "MacnitorCLICore",
            dependencies: [
                "MetricsKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .executableTarget(
            name: "MacnitorCLI",
            dependencies: ["MacnitorCLICore"]
        ),
        .executableTarget(
            name: "MetricsKitDemo",
            dependencies: ["MetricsKit"]
        ),
        .testTarget(
            name: "MetricsKitTests",
            dependencies: ["MetricsKit"]
        ),
        .testTarget(
            name: "MacnitorCLITests",
            dependencies: ["MacnitorCLICore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
