// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "pgpmana",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "pgpmana", targets: ["pgpmana"]),
        .library(name: "PgpassKit", targets: ["PgpassKit"]),
    ],
    targets: [
        .target(name: "PgpassKit"),
        .executableTarget(
            name: "pgpmana",
            dependencies: ["PgpassKit"],
            resources: [.copy("Resources/Fonts"), .copy("Resources/Images")]
        ),
        .testTarget(name: "PgpassKitTests", dependencies: ["PgpassKit"]),
    ]
)
