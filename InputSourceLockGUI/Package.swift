// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "InputSourceLockGUI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "InputSourceLockGUI",
            targets: ["InputSourceLockGUI"]
        )
    ],
    targets: [
        .executableTarget(
            name: "InputSourceLockGUI",
            dependencies: [],
            sources: ["InputSourceLockGUI"]
        )
    ]
)
