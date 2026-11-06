import Foundation

public struct KioskConfig {
    public let requiredMatches: Int
    public let staffCooldownMillis: Int64
    public let livenessTimeoutMillis: Int64
    public let trackExpiryMillis: Int64
    public let maxTracks: Int

    public init(
        requiredMatches: Int = 2,
        staffCooldownMillis: Int64 = 60_000,
        livenessTimeoutMillis: Int64 = 6_000,
        trackExpiryMillis: Int64 = 1_500,
        maxTracks: Int = 8
    ) {
        self.requiredMatches = requiredMatches
        self.staffCooldownMillis = staffCooldownMillis
        self.livenessTimeoutMillis = livenessTimeoutMillis
        self.trackExpiryMillis = trackExpiryMillis
        self.maxTracks = maxTracks
    }
}

public class KioskObservation {
    public let trackId: Int
    public let quality: QualityResult?
    public let isLive: Bool
    public let liveScore: Float
    public let embedding: [Float]?

    public init(trackId: Int, quality: QualityResult?, isLive: Bool, liveScore: Float, embedding: [Float]?) {
        self.trackId = trackId
        self.quality = quality
        self.isLive = isLive
        self.liveScore = liveScore
        self.embedding = embedding
    }
}

public enum KioskEvent {
    case matched(staffId: String)
    case spoof(reason: String)
}

public class KioskSession {
    private let recognizer: FaceRecognizer
    private let config: KioskConfig

    private var tracks: [Int: Int64] = [:]

    public init(recognizer: FaceRecognizer, config: KioskConfig = KioskConfig()) {
        self.recognizer = recognizer
        self.config = config
    }

    public func processFrame(observations: [KioskObservation]) -> [KioskEvent] {
        var events = [KioskEvent]()
        for obs in observations {
            if let quality = obs.quality, case .rejected(let issue) = quality {
                continue
            }
            if !obs.isLive {
                events.append(.spoof(reason: "Liveness Check Failed"))
                continue
            }

            guard let emb = obs.embedding else { continue }
            let result = recognizer.recognize(query: emb)

            if case .known(let staffId, _, _) = result {
                events.append(.matched(staffId: staffId))
            }
        }
        return events
    }
}
