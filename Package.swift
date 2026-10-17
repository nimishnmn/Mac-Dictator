// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacDictator",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacDictator", targets: ["MacDictator"]),
        .executable(name: "mac-dictator-cli", targets: ["MacDictatorCLI"])
    ],
    targets: [
        .target(
            name: "MacDictatorCore",
            dependencies: [],
            path: "Sources/MacDictatorCore"
        ),
        .executableTarget(
            name: "MacDictator",
            dependencies: ["MacDictatorCore"],
            path: "Sources/MacDictatorApp"
        ),
        .executableTarget(
            name: "MacDictatorCLI",
            dependencies: ["MacDictatorCore"],
            path: "Sources/MacDictatorCLI"
        )
    ]
)
