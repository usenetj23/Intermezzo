// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Intermezzo",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "IntermezzoKit", targets: ["IntermezzoKit"]),
        .executable(name: "Intermezzo", targets: ["IntermezzoApp"]),
    ],
    targets: [
        .target(name: "IntermezzoKit"),
        .executableTarget(
            name: "IntermezzoApp",
            dependencies: ["IntermezzoKit"]
        ),
        .testTarget(
            name: "IntermezzoKitTests",
            dependencies: ["IntermezzoKit"]
        ),
    ]
)
