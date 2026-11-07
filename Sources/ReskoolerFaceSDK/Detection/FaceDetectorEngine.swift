import Foundation

#if canImport(MLKitVision) && canImport(MLKitFaceDetection)
import MLKitFaceDetection
import MLKitVision

public class FaceDetectorEngine {
    private let detector: FaceDetector

    public init() {
        let options = FaceDetectorOptions()
        options.performanceMode = .fast
        options.landmarkMode = .all
        options.classificationMode = .all
        options.minFaceSize = 0.15
        options.isTrackingEnabled = true

        self.detector = FaceDetector.faceDetector(options: options)
    }

    public func process(
        image: VisionImage,
        onSuccess: @escaping ([Face]) -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        detector.process(image) { faces, error in
            if let error = error {
                onFailure(error)
                return
            }
            if let faces = faces {
                onSuccess(faces)
            } else {
                onSuccess([])
            }
        }
    }
}
#endif
