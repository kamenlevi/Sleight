// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Sleight",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CMultitouch"),
        .executableTarget(
            name: "Sleight",
            dependencies: ["CMultitouch"]
        ),
    ]
)
