// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "driveviewer",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "driveviewer", targets: ["driveviewer"])],
    targets: [
        .executableTarget(name: "driveviewer", path: "Sources"),
        .testTarget(name: "DriveviewerTests", dependencies: ["driveviewer"], path: "Tests")
    ]
)
