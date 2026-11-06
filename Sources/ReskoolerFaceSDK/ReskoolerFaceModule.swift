import Foundation
import ExpoModulesCore

public class ReskoolerFaceModule: Module {
    private var sdk: FaceSDK?

    public func definition() -> ModuleDefinition {
        Name("ReskoolerFace")

        Events("onFaceResult")

        AsyncFunction("startFaceSDK") { (modeString: String, promise: Promise) in
            do {
                if self.sdk == nil {
                    self.sdk = FaceSDK()
                }

                self.sdk?.onResult = { [weak self] result in
                    var payload: [String: Any] = [
                        "type": String(describing: result.type),
                        "confidence": result.confidence,
                        "liveness": result.liveness
                    ]

                    if let staffId = result.staffId {
                        payload["staffId"] = staffId
                    }
                    if let message = result.message {
                        payload["message"] = message
                    }
                    if let trackId = result.trackId {
                        payload["trackId"] = trackId
                    }
                    if let embedding = result.embedding {
                        payload["embedding"] = embedding
                    }

                    self?.sendEvent("onFaceResult", payload)
                }

                let mode: FaceSdkMode = (modeString.lowercased() == "enrollment") ? .enrollment : .kiosk
                self.sdk?.start(mode: mode)

                promise.resolve("Started")
            } catch {
                promise.reject("START_FAILED", "Failed to start Face SDK: \(error.localizedDescription)")
            }
        }

        AsyncFunction("stopFaceSDK") { (promise: Promise) in
            self.sdk?.stop()
            promise.resolve("Stopped")
        }

        AsyncFunction("setGallery") { (embeddings: [String: [[Float]]], promise: Promise) in
            self.sdk?.setGallery(embeddings: embeddings)
            promise.resolve("Gallery Updated")
        }
    }
}
