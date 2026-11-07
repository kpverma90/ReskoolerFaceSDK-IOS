import Foundation

public class EmbeddingGallery {
    public static let defaultDimension = 192
    public let dimension: Int

    private let queue = DispatchQueue(label: "com.reskooler.EmbeddingGallery", attributes: .concurrent)
    private var snapshot: [String: [[Float]]] = [:]

    public init(dimension: Int = EmbeddingGallery.defaultDimension) {
        self.dimension = dimension
    }

    public var staffCount: Int {
        var count = 0
        queue.sync { count = snapshot.count }
        return count
    }

    public var isEmpty: Bool {
        var empty = true
        queue.sync { empty = snapshot.isEmpty }
        return empty
    }

    public func entries() -> [String: [[Float]]] {
        var entriesCopy: [String: [[Float]]] = [:]
        queue.sync {
            entriesCopy = snapshot
        }
        return entriesCopy
    }

    public func put(staffId: String, embeddings: [[Float]]) {
        guard !staffId.isEmpty else { return }
        guard !embeddings.isEmpty else { return }

        let validated = validateAndCopy(staffId: staffId, embeddings: embeddings)
        queue.sync(flags: .barrier) {
            snapshot[staffId] = validated
        }
    }

    public func replaceAll(staff: [String: [[Float]]]) {
        var next = [String: [[Float]]]()
        for (staffId, embeddings) in staff {
            next[staffId] = validateAndCopy(staffId: staffId, embeddings: embeddings)
        }
        queue.sync(flags: .barrier) {
            snapshot = next
        }
    }

    public func remove(staffId: String) {
        queue.sync(flags: .barrier) {
            snapshot.removeValue(forKey: staffId)
        }
    }

    public func clear() {
        queue.sync(flags: .barrier) {
            snapshot.removeAll()
        }
    }

    private func validateAndCopy(staffId: String, embeddings: [[Float]]) -> [[Float]] {
        return embeddings.map { source in
            var copy = source
            if copy.count != dimension {
                // Invalid dimension
                return [] // Should throw, keeping it simple for port
            }
            if !normalizeInPlace(&copy) {
                return [] // Invalid embedding
            }
            return copy
        }.filter { !$0.isEmpty }
    }
}

internal func normalizeInPlace(_ vector: inout [Float]) -> Bool {
    var sum: Double = 0.0
    for value in vector {
        if value.isNaN || value.isInfinite {
            return false
        }
        sum += Double(value) * Double(value)
    }

    let norm = sqrt(sum)
    if norm <= 1e-6 {
        return false
    }

    for i in 0..<vector.count {
        vector[i] = Float(Double(vector[i]) / norm)
    }

    return true
}
