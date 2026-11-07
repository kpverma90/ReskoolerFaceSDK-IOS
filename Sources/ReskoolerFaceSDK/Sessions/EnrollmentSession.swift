import Foundation

public struct EnrollmentConfig {
    public let frontMaxYaw: Float
    public let turnMinYaw: Float
    public let turnMaxYaw: Float
    public let requiredStableFrames: Int
    public let duplicateThreshold: Float
    public let consistencyThreshold: Float

    public init(
        frontMaxYaw: Float = 12.0,
        turnMinYaw: Float = 15.0,
        turnMaxYaw: Float = 40.0,
        requiredStableFrames: Int = 3,
        duplicateThreshold: Float = 0.70,
        consistencyThreshold: Float = 0.45
    ) {
        self.frontMaxYaw = frontMaxYaw
        self.turnMinYaw = turnMinYaw
        self.turnMaxYaw = turnMaxYaw
        self.requiredStableFrames = requiredStableFrames
        self.duplicateThreshold = duplicateThreshold
        self.consistencyThreshold = consistencyThreshold
    }
}

public class EnrollmentFrame {
    public let faceCount: Int
    public let quality: QualityResult?
    public let yaw: Float
    public let isLive: Bool
    public let embedding: [Float]?

    public init(faceCount: Int, quality: QualityResult?, yaw: Float, isLive: Bool, embedding: [Float]?) {
        self.faceCount = faceCount
        self.quality = quality
        self.yaw = yaw
        self.isLive = isLive
        self.embedding = embedding
    }
}

public struct EnrollmentResultPayload {
    public let staffId: String
    public let embeddings: [[Float]]
}

public enum EnrollmentUpdateReason: String {
    case noFace = "NO_FACE"
    case multipleFaces = "MULTIPLE_FACES"
    case lowQuality = "LOW_QUALITY"
    case wrongPose = "WRONG_POSE"
    case checkingLiveness = "CHECKING_LIVENESS"
    case holdStill = "HOLD_STILL"
    case inconsistentFace = "INCONSISTENT_FACE"
    case invalidEmbedding = "INVALID_EMBEDDING"
}

public enum EnrollmentFailReason: String {
    case duplicateStaff = "DUPLICATE_STAFF"
}

public enum EnrollmentUpdate {
    case guidance(pose: EnrollmentPose, reason: EnrollmentUpdateReason, message: String)
    case captured(pose: EnrollmentPose, next: EnrollmentPose, message: String)
    case completed(result: EnrollmentResultPayload, message: String)
    case failed(reason: EnrollmentFailReason, message: String)
    case inactive

    public var message: String {
        switch self {
        case .guidance(_, _, let msg): return msg
        case .captured(_, _, let msg): return msg
        case .completed(_, let msg): return msg
        case .failed(_, let msg): return msg
        case .inactive: return ""
        }
    }
}

public class EnrollmentSession {
    public let staffId: String
    private let gallery: EmbeddingGallery?
    private let config: EnrollmentConfig

    private enum Phase { case active, completed, failed, cancelled }

    private let poses: [EnrollmentPose]
    private var captured: [[Float]] = []

    private var phase: Phase = .active
    private var stableFrames: Int = 0
    private var firstTurnSign: Int = 0

    private let stateLock = NSLock()

    public init(staffId: String, poses: [EnrollmentPose] = [.straight, .left, .right], gallery: EmbeddingGallery? = nil, config: EnrollmentConfig = EnrollmentConfig()) {
        self.staffId = staffId
        self.poses = poses
        self.gallery = gallery
        self.config = config
    }

    public func currentPose() -> EnrollmentPose? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return phase == .active && captured.count < poses.count ? poses[captured.count] : nil
    }

    public func isActive() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return phase == .active
    }

    public func poseMatches(yaw: Float) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        if phase != .active || captured.count >= poses.count { return false }
        return poseMatchesLocked(yaw: yaw, pose: poses[captured.count])
    }

    public func cancel() {
        stateLock.lock()
        defer { stateLock.unlock() }
        if phase == .active { phase = .cancelled }
    }

    public func onFrame(frame: EnrollmentFrame) -> EnrollmentUpdate {
        stateLock.lock()
        defer { stateLock.unlock() }

        if phase != .active || captured.count >= poses.count {
            return .inactive
        }

        let pose = poses[captured.count]

        let prompt: String
        switch pose {
        case .straight: prompt = "Look Straight"
        case .left: prompt = "Turn Left"
        case .right: prompt = "Turn Right"
        }

        func guide(reason: EnrollmentUpdateReason, message: String, resetStable: Bool = true) -> EnrollmentUpdate {
            if resetStable { stableFrames = 0 }
            return .guidance(pose: pose, reason: reason, message: message)
        }

        if frame.faceCount == 0 {
            return guide(reason: .noFace, message: "No face detected")
        }

        if frame.faceCount > 1 {
            return guide(reason: .multipleFaces, message: "Only one person please")
        }

        if let quality = frame.quality, case .rejected(let issue) = quality {
            return guide(reason: .lowQuality, message: issue.rawValue)
        }

        if !poseMatchesLocked(yaw: frame.yaw, pose: pose) {
            return guide(reason: .wrongPose, message: prompt)
        }

        if !frame.isLive {
            return guide(reason: .checkingLiveness, message: "Hold still...")
        }

        stableFrames += 1

        guard let embedding = frame.embedding else {
            return guide(reason: .holdStill, message: "Hold still...", resetStable: false)
        }

        if stableFrames < config.requiredStableFrames {
            return guide(reason: .holdStill, message: "Hold still...", resetStable: false)
        }

        var candidate = embedding
        if candidate.count != captureDimension() || !normalizeInPlace(&candidate) {
            return guide(reason: .invalidEmbedding, message: "Try again")
        }

        if isDuplicateOfAnotherStaff(candidate: candidate) {
            phase = .failed
            return .failed(reason: .duplicateStaff, message: "This face is already enrolled")
        }

        if !captured.isEmpty && FaceSimilarity.cosineSimilarity(first: captured[0], second: candidate) < config.consistencyThreshold {
            return guide(reason: .inconsistentFace, message: "Same person must finish all poses")
        }

        captured.append(candidate)
        stableFrames = 0

        if pose == .left || pose == .right {
            if firstTurnSign == 0 {
                firstTurnSign = signOf(yaw: frame.yaw)
            }
        }

        if captured.count == poses.count {
            phase = .completed
            return .completed(result: EnrollmentResultPayload(staffId: staffId, embeddings: captured), message: "Enrollment Complete")
        }

        let next = poses[captured.count]
        let nextPrompt: String
        switch next {
        case .straight: nextPrompt = "Look Straight"
        case .left: nextPrompt = "Turn Left"
        case .right: nextPrompt = "Turn Right"
        }

        return .captured(pose: pose, next: next, message: "Captured. \(nextPrompt)")
    }

    private func poseMatchesLocked(yaw: Float, pose: EnrollmentPose) -> Bool {
        if yaw.isNaN { return false }
        switch pose {
        case .straight:
            return abs(yaw) <= config.frontMaxYaw
        case .left:
            return abs(yaw) >= config.turnMinYaw && abs(yaw) <= config.turnMaxYaw
        case .right:
            return abs(yaw) >= config.turnMinYaw && abs(yaw) <= config.turnMaxYaw && signOf(yaw: yaw) == -firstTurnSign
        }
    }

    private func signOf(yaw: Float) -> Int {
        return yaw >= 0.0 ? 1 : -1
    }

    private func captureDimension() -> Int {
        return gallery?.dimension ?? 192
    }

    private func isDuplicateOfAnotherStaff(candidate: [Float]) -> Bool {
        guard let gallery = gallery else { return false }
        for (otherId, embeddings) in gallery.entries() {
            if otherId == staffId { continue }
            for reference in embeddings {
                if FaceSimilarity.cosineSimilarity(first: reference, second: candidate) >= config.duplicateThreshold {
                    return true
                }
            }
        }
        return false
    }
}
