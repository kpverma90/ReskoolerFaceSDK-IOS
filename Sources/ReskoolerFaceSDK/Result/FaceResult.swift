import Foundation

public enum FaceResult {
    case success(staffId: String, similarity: Float, liveness: Float, timestampMillis: Int64)
    case unknown(reason: String)
    case spoof(reason: String)
    case noFace(reason: String)
    case multipleFaces(reason: String)
    case lowQuality(reason: String)
    case error(message: String)

    public static func fromRecognition(
        recognition: RecognitionResult,
        liveness: Float,
        timestampMillis: Int64
    ) -> FaceResult {
        switch recognition {
        case .known(let staffId, let similarity, _):
            return .success(staffId: staffId, similarity: similarity, liveness: liveness, timestampMillis: timestampMillis)
        case .unknown(let reason, _):
            return .unknown(reason: reason.rawValue)
        }
    }

    public static func fromQuality(issue: QualityIssue) -> FaceResult {
        return .lowQuality(reason: issue.rawValue)
    }
}
