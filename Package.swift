// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Meowse",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Meowse", targets: ["Meowse"]),
        .executable(name: "MeowseSettings", targets: ["MeowseSettings"]),
    ],
    targets: [
        .target(name: "MeowseCore"),
        .executableTarget(
            name: "Meowse",
            dependencies: ["MeowseCore"]
        ),
        // The Settings window, a separate process that exits when it closes.
        .executableTarget(
            name: "MeowseSettings",
            dependencies: ["MeowseCore"]
        ),
        .testTarget(
            name: "MeowseCoreTests",
            dependencies: ["MeowseCore"]
        ),
    ]
)
