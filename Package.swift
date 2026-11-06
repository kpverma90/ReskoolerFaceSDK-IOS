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
        // MLKit is heavily distributed via CocoaPods.
        // For standard Swift Package Manager resolution, we cannot pull MLKit natively.
        // To allow local structure passing, we rely on the host application to provide the Framework linkage,
        // or provide the TensorFlowLite wrapper.
        .package(url: "https://github.com/tensorflow/tensorflow-lite-swift.git", from: "0.2.0")
    ],
    targets: [
        .target(
            name: "ReskoolerFaceSDK",
            dependencies: [
                .product(name: "TensorFlowLite", package: "tensorflow-lite-swift")
            ],
            resources: [
                .process("Models")
            ]),
        .testTarget(
            name: "ReskoolerFaceSDKTests",
            dependencies: ["ReskoolerFaceSDK"]),
    ]
)
