// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReskoolerFaceSDK",
    platforms: [
        .iOS(.v13)
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
            ]),
        .testTarget(
            name: "ReskoolerFaceSDKTests",
            dependencies: ["ReskoolerFaceSDK"]),
    ]
)
