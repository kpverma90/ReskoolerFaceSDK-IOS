
import Foundation

public enum EnrollmentReason {
    case noFace
    case multipleFaces
    case lowQuality
    case wrongPose
    case checkingLiveness
    case holdStill
    case inconsistentFace
    case invalidEmbedding
}

public enum EnrollmentFailReason {
    case duplicateStaff
}

public struct EnrollmentConfig {
    public var frontMaxYaw: Float = 12
    public var turnMinYaw: Float = 15
    public var turnMaxYaw: Float = 40
    public var requiredStableFrames: Int = 3
    public var duplicateThreshold: Float = 0.70
    public var consistencyThreshold: Float = 0.45

    public init() {}
}

public struct EnrollmentFrame {
    public let faceCount: Int
    public let quality: QualityResult?
    public let yaw: Float
    public let isLive: Bool
    public let embedding: [Float]?

    public init(
        faceCount: Int,
        quality: QualityResult?,
        yaw: Float,
        isLive: Bool,
        embedding: [Float]?
    ) {
        self.faceCount = faceCount
        self.quality = quality
        self.yaw = yaw
        self.isLive = isLive
        self.embedding = embedding
    }
}

public struct EnrollmentResult {
    public let staffId: String
    public let embeddings: [[Float]]

    public init(staffId: String, embeddings: [[Float]]) {
        self.staffId = staffId
        self.embeddings = embeddings
    }
}

public enum EnrollmentUpdate {
    case guidance(
        pose: EnrollmentPose,
        reason: EnrollmentReason,
        message: String
    )

    case captured(
        pose: EnrollmentPose,
        next: EnrollmentPose,
        message: String
    )

    case completed(EnrollmentResult)

    case failed(
        reason: EnrollmentFailReason,
        message: String
    )

    case inactive
}

public final class EnrollmentSession {

    private enum Phase {
        case active
        case completed
        case failed
        case cancelled
    }

    private let lock = NSLock()

    private let staffId: String
    private let gallery: EmbeddingGallery?
    private let config: EnrollmentConfig

    private let poses: [EnrollmentPose] = [
        .straight,
        .left,
        .right
    ]

    private var captured: [[Float]] = []
    private var phase: Phase = .active
    private var stableFrames = 0
    private var firstTurnSign: Float = 0

    public init(
        staffId: String,
        gallery: EmbeddingGallery? = nil,
        config: EnrollmentConfig = EnrollmentConfig()
    ) {
        self.staffId = staffId
        self.gallery = gallery
        self.config = config
    }

    public func currentPose() -> EnrollmentPose? {
        lock.lock()
        defer { lock.unlock() }

        guard phase == .active,
              captured.count < poses.count else {
            return nil
        }

        return poses[captured.count]
    }

    public func isActive() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return phase == .active
    }

    public func cancel() {
        lock.lock()
        defer { lock.unlock() }

        if phase == .active {
            phase = .cancelled
            stableFrames = 0
        }
    }

    public func poseMatches(yaw: Float) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard phase == .active,
              captured.count < poses.count else {
            return false
        }

        return poseMatchesLocked(
            yaw: yaw,
            pose: poses[captured.count]
        )
    }

    public func onFrame(_ frame: EnrollmentFrame) -> EnrollmentUpdate {
        lock.lock()
        defer { lock.unlock() }

        guard phase == .active,
              captured.count < poses.count else {
            return .inactive
        }

        let pose = poses[captured.count]

        func guidance(
            _ reason: EnrollmentReason,
            _ message: String
        ) -> EnrollmentUpdate {
            stableFrames = 0
            return .guidance(
                pose: pose,
                reason: reason,
                message: message
            )
        }

        if frame.faceCount == 0 {
            return guidance(.noFace, "No face detected")
        }

        if frame.faceCount > 1 {
            return guidance(.multipleFaces, "Only one person please")
        }

        guard let quality = frame.quality else {
            return guidance(.lowQuality, "Face not readable")
        }

        switch quality {
        case .ok:
            break

        case .rejected(let issue):
            return guidance(
                .lowQuality,
                qualityMessage(issue)
            )
        }

        guard poseMatchesLocked(yaw: frame.yaw, pose: pose) else {
            return guidance(
                .wrongPose,
                posePrompt(pose)
            )
        }

        guard frame.isLive else {
            return guidance(
                .checkingLiveness,
                "Hold still..."
            )
        }

        stableFrames += 1

        guard stableFrames >= config.requiredStableFrames,
              let sourceEmbedding = frame.embedding else {
            return .guidance(
                pose: pose,
                reason: .holdStill,
                message: "Hold still..."
            )
        }

        var candidate = sourceEmbedding

        let dimension = gallery?.dimension
            ?? EmbeddingGallery.defaultDimension

        guard candidate.count == dimension,
              normalizeInPlace(&candidate) else {
            return guidance(
                .invalidEmbedding,
                "Try again"
            )
        }

        if isDuplicateOfAnotherStaff(candidate) {
            phase = .failed
            stableFrames = 0

            return .failed(
                reason: .duplicateStaff,
                message: "This face is already enrolled"
            )
        }

        if let firstEmbedding = captured.first {
            let similarity = cosineSimilarity(
                candidate,
                firstEmbedding
            )

            if similarity < config.consistencyThreshold {
                return guidance(
                    .inconsistentFace,
                    "Same person must finish all poses"
                )
            }
        }

        captured.append(candidate)
        stableFrames = 0

        if captured.count == poses.count {
            phase = .completed

            return .completed(
                EnrollmentResult(
                    staffId: staffId,
                    embeddings: captured.map { $0 }
                )
            )
        }

        let nextPose = poses[captured.count]

        return .captured(
            pose: pose,
            next: nextPose,
            message: "Captured. \(posePrompt(nextPose))"
        )
    }

    private func poseMatchesLocked(
        yaw: Float,
        pose: EnrollmentPose
    ) -> Bool {

        guard yaw.isFinite else {
            return false
        }

        let absoluteYaw = abs(yaw)

        switch pose {

        case .straight:
            return absoluteYaw <= config.frontMaxYaw

        case .left:
            let valid = absoluteYaw >= config.turnMinYaw
                && absoluteYaw <= config.turnMaxYaw

            if valid && firstTurnSign == 0 {
                firstTurnSign = yaw >= 0 ? 1 : -1
            }

            return valid

        case .right:
            let valid = absoluteYaw >= config.turnMinYaw
                && absoluteYaw <= config.turnMaxYaw

            guard valid, firstTurnSign != 0 else {
                return false
            }

            let currentSign: Float = yaw >= 0 ? 1 : -1

            return currentSign == -firstTurnSign
        }
    }

    private func isDuplicateOfAnotherStaff(
        _ candidate: [Float]
    ) -> Bool {

        guard let gallery = gallery else {
            return false
        }

        let entries = gallery.entries()

        for (existingStaffId, embeddings) in entries {

            if existingStaffId == staffId {
                continue
            }

            for existing in embeddings {
                let similarity = cosineSimilarity(
                    candidate,
                    existing
                )

                if similarity >= config.duplicateThreshold {
                    return true
                }
            }
        }

        return false
    }

    private func cosineSimilarity(
        _ first: [Float],
        _ second: [Float]
    ) -> Float {

        guard first.count == second.count,
              !first.isEmpty else {
            return 0
        }

        var dot: Float = 0
        var firstNorm: Float = 0
        var secondNorm: Float = 0

        for index in first.indices {
            dot += first[index] * second[index]
            firstNorm += first[index] * first[index]
            secondNorm += second[index] * second[index]
        }

        guard firstNorm > 0, secondNorm > 0 else {
            return 0
        }

        return dot / (sqrt(firstNorm) * sqrt(secondNorm))
    }

    private func posePrompt(_ pose: EnrollmentPose) -> String {
        switch pose {
        case .straight:
            return "Look Straight"
        case .left:
            return "Turn Left"
        case .right:
            return "Turn Right"
        }
    }

    private func qualityMessage(_ issue: QualityIssue) -> String {
        switch issue {
        case .invalidFace:
            return "Face not readable"
        case .tooSmall:
            return "Move closer to the camera"
        case .partialFace:
            return "Keep your whole face in the frame"
        case .extremePose:
            return "Look at the camera"
        }
    }
}
