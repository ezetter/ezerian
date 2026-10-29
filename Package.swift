// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ezerian",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Ezerian",
            path: "Sources/Ezerian",
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]
        )
    ]
)
