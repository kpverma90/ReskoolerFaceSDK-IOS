
import Foundation

// MARK: - SDK Mode

public enum FaceSdkMode: String {
    case enrollment = "enrollment"
    case selfAttendance = "selfAttendance"
    case kiosk = "kiosk"
}

// MARK: - Enrollment Pose

public enum EnrollmentPose: String {
    case straight = "STRAIGHT"
    case left = "LEFT"
    case right = "RIGHT"
}

// MARK: - Result Type

public enum FaceSdkResultType: String {
    case success = "SUCCESS"
    case matched = "MATCHED"
    case noFace = "NO_FACE"
    case multipleFaces = "MULTIPLE_FACES"
    case lowQuality = "LOW_QUALITY"
    case notRecognized = "NOT_RECOGNIZED"
    case spoofSuspected = "SPOOF_SUSPECTED"
    case scanning = "SCANNING"
    case error = "ERROR"
}

// MARK: - Face SDK Result

public struct FaceSdkResult {

    public let type: FaceSdkResultType
    public let confidence: Float
    public let liveness: Float

    public let staffId: String?

    public let embedding: [Float]?
    public let enrollmentEmbeddings: [[Float]]?

    public let pose: EnrollmentPose?
    public let message: String?
    public let trackId: Int?

    public init(
        type: FaceSdkResultType,
        confidence: Float = 0.0,
        liveness: Float = 0.0,
        staffId: String? = nil,
        embedding: [Float]? = nil,
        enrollmentEmbeddings: [[Float]]? = nil,
        pose: EnrollmentPose? = nil,
        message: String? = nil,
        trackId: Int? = nil
    ) {

        self.type = type
        self.confidence = confidence
        self.liveness = liveness
        self.staffId = staffId
        self.embedding = embedding
        self.enrollmentEmbeddings = enrollmentEmbeddings
        self.pose = pose
        self.message = message
        self.trackId = trackId
    }
}

// MARK: - SDK Configuration

public struct FaceSdkConfig {

    public let matchThreshold: Float
    public let enrollmentPoses: [EnrollmentPose]

    public init(
        matchThreshold: Float = 0.70,
        enrollmentPoses: [EnrollmentPose] = [
            .straight,
            .left,
            .right
        ]
    ) {

        self.matchThreshold = matchThreshold
        self.enrollmentPoses = enrollmentPoses
    }
}
