import Foundation

public struct FaceSimilarity {
    public static func cosineSimilarity(first: [Float], second: [Float]) -> Float {
        guard first.count == second.count else {
            return 0.0
        }

        var dot: Double = 0.0
        var firstNorm: Double = 0.0
        var secondNorm: Double = 0.0

        for i in 0..<first.count {
            let a = Double(first[i])
            let b = Double(second[i])

            dot += a * b
            firstNorm += a * a
            secondNorm += b * b
        }

        if firstNorm <= 0.0 || secondNorm <= 0.0 {
            return 0.0
        }

        return Float(dot / (sqrt(firstNorm) * sqrt(secondNorm)))
    }
}
