// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EchoFetch",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "EchoFetchCore", targets: ["EchoFetchCore"]),
        .executable(name: "EchoFetchApp", targets: ["EchoFetchApp"])
    ],
    targets: [
        .target(name: "EchoFetchCore"),
        .executableTarget(name: "EchoFetchApp", dependencies: ["EchoFetchCore"]),
        .testTarget(name: "EchoFetchTests", dependencies: ["EchoFetchCore"])
    ]
)
