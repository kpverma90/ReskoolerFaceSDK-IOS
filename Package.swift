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
        // Since Google ML Kit does not natively support Swift Package Manager and requires CocoaPods,
        // this Package.swift is provided solely for basic directory structural compliance and tests that mock the SDK.
        // For actual production builds, you MUST use CocoaPods and the provided `ReskoolerFaceSDK.podspec`.
        .target(
            name: "ReskoolerFaceSDK",
            dependencies: [],
            resources: [
                .process("Models")
            ],
            swiftSettings: [
                .define("COCOAPODS", .when(configuration: .release)) // Ensure SPM builds are effectively skipped if attempted natively
            ]),
        .testTarget(
            name: "ReskoolerFaceSDKTests",
            dependencies: ["ReskoolerFaceSDK"]),
    ]
)
