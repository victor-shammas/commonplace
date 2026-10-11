// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CommonplaceHelper",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "CommonplaceHelper", path: "Sources")
    ]
)
