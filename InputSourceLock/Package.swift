// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "InputSourceLock",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "InputSourceLock",
            targets: ["InputSourceLock"]
        )
    ],
    targets: [
        .executableTarget(
            name: "InputSourceLock",
            dependencies: [],
            sources: ["InputSourceLock/main.swift"]
        )
    ]
)
