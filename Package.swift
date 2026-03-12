// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Crystl",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.11.0")
    ],
    targets: [
        .executableTarget(
            name: "Crystl",
            dependencies: ["SwiftTerm"],
            path: "Sources/Crystl"
        )
    ]
)
