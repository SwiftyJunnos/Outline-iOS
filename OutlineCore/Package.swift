// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OutlineCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "OutlineCore", targets: ["OutlineCore"])
    ],
    targets: [
        .target(name: "OutlineCore"),
        .testTarget(name: "OutlineCoreTests", dependencies: ["OutlineCore"])
    ]
)
