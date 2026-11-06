import Foundation

public enum FaceSdkMode {
    case enrollment
    case selfAttendance
    case kiosk
}

public enum EnrollmentPose {
    case straight
    case left
    case right
}

public enum FaceSdkResultType {
    case success
    case matched
    case noFace
    case multipleFaces
    case lowQuality
    case notRecognized
    case spoofSuspected
    case scanning
    case error
}

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

public struct FaceSdkConfig {
    public let matchThreshold: Float
    public let enrollmentPoses: [EnrollmentPose]

    public init(
        matchThreshold: Float = 0.70,
        enrollmentPoses: [EnrollmentPose] = [.straight, .left, .right]
    ) {
        self.matchThreshold = matchThreshold
        self.enrollmentPoses = enrollmentPoses
    }
}
