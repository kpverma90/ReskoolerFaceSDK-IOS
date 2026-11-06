import Foundation

public struct SelfAttendanceConfig {
    public let requiredMatches: Int
    public let unknownFramesToDecide: Int
    public let livenessTimeoutMillis: Int64
    public let sessionTimeoutMillis: Int64

    public init(
        requiredMatches: Int = 2,
        unknownFramesToDecide: Int = 4,
        livenessTimeoutMillis: Int64 = 6_000,
        sessionTimeoutMillis: Int64 = 15_000
    ) {
        self.requiredMatches = requiredMatches
        self.unknownFramesToDecide = unknownFramesToDecide
        self.livenessTimeoutMillis = livenessTimeoutMillis
        self.sessionTimeoutMillis = sessionTimeoutMillis
    }
}

public class AttendanceFrame {
    public let faceCount: Int
    public let quality: QualityResult?
    public let isLive: Bool
    public let liveScore: Float
    public let embedding: [Float]?

    public init(faceCount: Int, quality: QualityResult?, isLive: Bool, liveScore: Float, embedding: [Float]?) {
        self.faceCount = faceCount
        self.quality = quality
        self.isLive = isLive
        self.liveScore = liveScore
        self.embedding = embedding
    }
}

public class SelfAttendanceSession {
    private let recognizer: FaceRecognizer
    private let config: SelfAttendanceConfig

    private var consecutiveMatches = 0
    private var consecutiveUnknowns = 0
    private var startTime: Int64
    private var firstFaceTime: Int64?

    public init(recognizer: FaceRecognizer, config: SelfAttendanceConfig = SelfAttendanceConfig()) {
        self.recognizer = recognizer
        self.config = config
        self.startTime = Int64(Date().timeIntervalSince1970 * 1000)
    }

    public func processFrame(frame: AttendanceFrame) -> FaceSdkResult? {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if now - startTime > config.sessionTimeoutMillis {
            return FaceSdkResult(type: .error, message: "Session Timeout")
        }

        if frame.faceCount == 0 {
            return nil
        }
        if frame.faceCount > 1 {
            return FaceSdkResult(type: .multipleFaces)
        }

        if firstFaceTime == nil {
            firstFaceTime = now
        }

        if let quality = frame.quality, case .rejected(let issue) = quality {
            return FaceSdkResult(type: .lowQuality, message: issue.rawValue)
        }

        if !frame.isLive {
            if let first = firstFaceTime, now - first > config.livenessTimeoutMillis {
                return FaceSdkResult(type: .spoofSuspected, liveness: frame.liveScore)
            }
            return nil
        }

        guard let emb = frame.embedding else { return nil }

        let result = recognizer.recognize(query: emb)

        switch result {
        case .known(let staffId, let similarity, _):
            consecutiveMatches += 1
            if consecutiveMatches >= config.requiredMatches {
                return FaceSdkResult(type: .success, confidence: similarity, liveness: frame.liveScore, staffId: staffId, embedding: emb)
            }
        case .unknown(let reason, let bestScore):
            consecutiveUnknowns += 1
            if consecutiveUnknowns >= config.unknownFramesToDecide {
                return FaceSdkResult(type: .notRecognized, confidence: bestScore ?? 0.0, message: reason.rawValue)
            }
        }
        return nil
    }
}
