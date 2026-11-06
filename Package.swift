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
    dependencies: [
        .package(url: "https://github.com/google/mlkit.git", from: "3.2.0"), // ML Kit Vision/Face Mock Link
        .package(url: "https://github.com/tensorflow/tensorflow-lite-swift.git", from: "0.2.0"),
        .package(url: "https://github.com/expo/expo.git", from: "51.0.0") // Expo Module core
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
