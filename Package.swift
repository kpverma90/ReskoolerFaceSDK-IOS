// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReskoolerFaceSDK",
    platforms: [
        .iOS(.v13), .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "ReskoolerFaceSDK",
            targets: ["ReskoolerFaceSDK"]),
    ],
    targets: [
        .target(
            name: "ReskoolerFaceSDK",
            dependencies: [],
            resources: [
                .process("Models")
            ],
            swiftSettings: [
                .define("COCOAPODS", .when(configuration: .release))
            ]),
        .testTarget(
            name: "ReskoolerFaceSDKTests",
            dependencies: ["ReskoolerFaceSDK"]),
    ]
)
