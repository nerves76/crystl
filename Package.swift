// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Crystl",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.11.0")
    ],
    targets: [
        .target(
            name: "CrystlLib",
            dependencies: ["SwiftTerm"],
            path: "Sources/Crystl",
            exclude: ["main.swift"]
        ),
        .executableTarget(
            name: "Crystl",
            dependencies: ["CrystlLib"],
            path: "Sources/CrystlApp"
        ),
        .testTarget(
            name: "CrystlTests",
            dependencies: ["CrystlLib"],
            path: "Tests/CrystlTests"
        )
    ]
)
