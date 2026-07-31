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
        // Root launchd daemon that books the wakes automations need. Kept
        // deliberately separate from the app and dependency-free: it runs as
        // root, so the less of it there is, the better.
        .executableTarget(
            name: "sleight-helper",
            path: "Sources/SleightHelper"
        ),
    ]
)
