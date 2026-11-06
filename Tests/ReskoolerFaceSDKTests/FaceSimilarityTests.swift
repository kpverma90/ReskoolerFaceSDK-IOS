import XCTest
@testable import ReskoolerFaceSDK

final class FaceSimilarityTests: XCTestCase {
    func testCosineSimilarityIdentical() {
        let first: [Float] = [1.0, 2.0, 3.0]
        let second: [Float] = [1.0, 2.0, 3.0]

        let score = FaceSimilarity.cosineSimilarity(first: first, second: second)
        XCTAssertEqual(score, 1.0, accuracy: 0.0001)
    }

    func testCosineSimilarityOrthogonal() {
        let first: [Float] = [1.0, 0.0, 0.0]
        let second: [Float] = [0.0, 1.0, 0.0]

        let score = FaceSimilarity.cosineSimilarity(first: first, second: second)
        XCTAssertEqual(score, 0.0, accuracy: 0.0001)
    }
}
