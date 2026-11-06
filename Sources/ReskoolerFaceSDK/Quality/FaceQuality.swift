import Foundation

public struct FaceMetrics {
    public let left: Float
    public let top: Float
    public let right: Float
    public let bottom: Float
    public let frameWidth: Int
    public let frameHeight: Int
    public let yaw: Float
    public let pitch: Float
    public let roll: Float

    public init(left: Float, top: Float, right: Float, bottom: Float, frameWidth: Int, frameHeight: Int, yaw: Float, pitch: Float, roll: Float) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
    }
}

public struct QualityConfig {
    public let minFaceWidthRatio: Float
    public let minFaceAreaRatio: Float
    public let edgeTolerance: Float
    public let maxYawDegrees: Float
    public let maxPitchDegrees: Float
    public let maxRollDegrees: Float

    public init(
        minFaceWidthRatio: Float = 0.14,
        minFaceAreaRatio: Float = 0.018,
        edgeTolerance: Float = 0.01,
        maxYawDegrees: Float = 40.0,
        maxPitchDegrees: Float = 30.0,
        maxRollDegrees: Float = 35.0
    ) {
        self.minFaceWidthRatio = minFaceWidthRatio
        self.minFaceAreaRatio = minFaceAreaRatio
        self.edgeTolerance = edgeTolerance
        self.maxYawDegrees = maxYawDegrees
        self.maxPitchDegrees = maxPitchDegrees
        self.maxRollDegrees = maxRollDegrees
    }
}

public enum QualityIssue: String {
    case invalidFace = "Face not readable"
    case tooSmall = "Move closer to the camera"
    case partialFace = "Keep your whole face in the frame"
    case extremePose = "Look at the camera"
}

public enum QualityResult {
    case ok
    case rejected(issue: QualityIssue)
}

public class FaceQualityGate {
    private let config: QualityConfig

    public init(config: QualityConfig = QualityConfig()) {
        self.config = config
    }

    public func evaluate(m: FaceMetrics) -> QualityResult {
        let width = m.right - m.left
        let height = m.bottom - m.top

        let valid = m.frameWidth > 0 &&
                    m.frameHeight > 0 &&
                    width > 1.0 &&
                    height > 1.0 &&
                    !m.yaw.isNaN &&
                    !m.pitch.isNaN &&
                    !m.roll.isNaN

        if !valid {
            return .rejected(issue: .invalidFace)
        }

        let frameW = Float(m.frameWidth)
        let frameH = Float(m.frameHeight)

        if (width / frameW < config.minFaceWidthRatio) || ((width * height) / (frameW * frameH) < config.minFaceAreaRatio) {
            return .rejected(issue: .tooSmall)
        }

        let tolX = frameW * config.edgeTolerance
        let tolY = frameH * config.edgeTolerance

        if m.left < -tolX ||
           m.top < -tolY ||
           m.right > frameW + tolX ||
           m.bottom > frameH + tolY {
            return .rejected(issue: .partialFace)
        }

        if abs(m.yaw) > config.maxYawDegrees ||
           abs(m.pitch) > config.maxPitchDegrees ||
           abs(m.roll) > config.maxRollDegrees {
            return .rejected(issue: .extremePose)
        }

        return .ok
    }
}
