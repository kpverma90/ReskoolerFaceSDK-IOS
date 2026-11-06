import Foundation

public struct RecognizerConfig {
    public let threshold: Float
    public let minMargin: Float

    public init(threshold: Float = 0.70, minMargin: Float = 0.05) {
        self.threshold = threshold
        self.minMargin = minMargin
    }
}

public enum RecognitionResult {
    case known(staffId: String, similarity: Float, embeddingIndex: Int)
    case unknown(reason: Reason, bestSimilarity: Float? = nil)

    public enum Reason: String {
        case emptyGallery = "EMPTY_GALLERY"
        case invalidQuery = "INVALID_QUERY"
        case belowThreshold = "BELOW_THRESHOLD"
        case ambiguous = "AMBIGUOUS"
    }
}

public class FaceRecognizer {
    private let gallery: EmbeddingGallery
    private let config: RecognizerConfig

    public init(gallery: EmbeddingGallery, config: RecognizerConfig = RecognizerConfig()) {
        self.gallery = gallery
        self.config = config
    }

    public func recognize(query: [Float]) -> RecognitionResult {
        let staff = gallery.entries()

        if staff.isEmpty {
            return .unknown(reason: .emptyGallery)
        }

        if query.count != gallery.dimension {
            return .unknown(reason: .invalidQuery)
        }

        var normalizedQuery = query
        if !normalizeInPlace(&normalizedQuery) {
            return .unknown(reason: .invalidQuery)
        }

        var bestId: String? = nil
        var bestScore: Float = -2.0
        var bestIndex = -1
        var secondBestScore: Float = -2.0

        for (staffId, embeddings) in staff {
            var staffScore: Float = -2.0
            var staffIndex = -1

            for i in 0..<embeddings.count {
                let score = FaceSimilarity.cosineSimilarity(first: embeddings[i], second: normalizedQuery)
                if score > staffScore {
                    staffScore = score
                    staffIndex = i
                }
            }

            if staffScore > bestScore {
                secondBestScore = bestScore
                bestScore = staffScore
                bestId = staffId
                bestIndex = staffIndex
            } else if staffScore > secondBestScore {
                secondBestScore = staffScore
            }
        }

        guard let bestStaffId = bestId else {
            return .unknown(reason: .emptyGallery)
        }

        if bestScore < config.threshold {
            return .unknown(reason: .belowThreshold, bestSimilarity: bestScore)
        }

        if staff.count >= 2 && (bestScore - secondBestScore < config.minMargin) {
            return .unknown(reason: .ambiguous, bestSimilarity: bestScore)
        }

        return .known(staffId: bestStaffId, similarity: bestScore, embeddingIndex: bestIndex)
    }
}
