// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BlazeEngine",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "BlazeEngine", targets: ["BlazeEngine"]),
        .executable(name: "blazecli", targets: ["blazecli"])
    ],
    targets: [
        .target(name: "BlazeEngine"),
        .executableTarget(name: "blazecli", dependencies: ["BlazeEngine"]),
        .testTarget(name: "BlazeEngineTests", dependencies: ["BlazeEngine"])
    ],
    swiftLanguageVersions: [.v5]
)
