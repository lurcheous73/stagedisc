// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StageDisc",
    platforms: [.macOS(.v14)],
    products: [.library(name: "StageDiscCore", targets: ["StageDiscCore"]), .executable(name: "StageDisc", targets: ["StageDisc"]),
               .executable(name: "stage-disc-cli", targets: ["StageDiscCLI"])],
    targets: [
        .target(name: "StageDiscCore"),
        .executableTarget(name: "StageDisc", dependencies: ["StageDiscCore"]),
        .executableTarget(name: "StageDiscCLI", dependencies: ["StageDiscCore"]),
        .testTarget(name: "StageDiscCoreTests", dependencies: ["StageDiscCore"])
    ]
)
