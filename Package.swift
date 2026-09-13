// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CreateEvent",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CreateEvent", targets: ["CreateEvent"])],
    targets: [
        .target(name: "EventCore"),
        .executableTarget(name: "CreateEvent", dependencies: ["EventCore"]),
        .testTarget(name: "EventCoreTests", dependencies: ["EventCore"])
    ]
)
