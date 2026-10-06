// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Meowse",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Meowse", targets: ["Meowse"]),
    ],
    targets: [
        .target(name: "MeowseCore"),
        .executableTarget(
            name: "Meowse",
            dependencies: ["MeowseCore"]
        ),
        .testTarget(
            name: "MeowseCoreTests",
            dependencies: ["MeowseCore"]
        ),
    ]
)
