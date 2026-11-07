import Foundation

extension Foundation.Bundle {
    static nonisolated let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("ReskoolerFaceSDK_ReskoolerFaceSDK.resources").path
        let buildPath = "F:\\My Apps\\ReskoolerFaceSDK-iOS\\.build\\index-build\\x86_64-unknown-windows-msvc\\debug\\ReskoolerFaceSDK_ReskoolerFaceSDK.resources"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}