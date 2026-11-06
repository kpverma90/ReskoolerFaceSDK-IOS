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

    // Internal track state for debouncing and cooldown
    private struct KioskTrackState {
        var consecutiveMatches: Int = 0
        var matchedStaffId: String? = nil
        var lastMatchedTime: Int64 = 0
    }

    private var trackStates: [Int: KioskTrackState] = [:]

    public init(recognizer: FaceRecognizer, config: KioskConfig = KioskConfig()) {
        self.recognizer = recognizer
        self.config = config
    }

    public func processFrame(observations: [KioskObservation]) -> [KioskEvent] {
        var events = [KioskEvent]()
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        for obs in observations {
            if let quality = obs.quality, case .rejected = quality {
                continue
            }

            if !obs.isLive {
                events.append(.spoof(reason: "Liveness Check Failed"))
                continue
            }

            guard let emb = obs.embedding else { continue }
            let result = recognizer.recognize(query: emb)

            var state = trackStates[obs.trackId] ?? KioskTrackState()

            if case .known(let staffId, _, _) = result {
                // If the same staff is already in cooldown for this track, skip event spam
                if state.matchedStaffId == staffId && now - state.lastMatchedTime < config.staffCooldownMillis {
                    continue
                }

                state.consecutiveMatches += 1
                if state.consecutiveMatches >= config.requiredMatches {
                    events.append(.matched(staffId: staffId))
                    state.matchedStaffId = staffId
                    state.lastMatchedTime = now
                    state.consecutiveMatches = 0 // Reset matches to enter cooldown properly
                }
            } else {
                state.consecutiveMatches = 0
            }

            trackStates[obs.trackId] = state
        }

        // Expiry of abandoned tracks could be handled here in a robust implementation,
        // omitted here for brevity since TrackSession usually purges dead tracks.
        return events
    }
}
