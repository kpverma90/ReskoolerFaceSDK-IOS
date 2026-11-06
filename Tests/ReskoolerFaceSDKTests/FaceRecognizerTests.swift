import XCTest
@testable import ReskoolerFaceSDK

final class FaceRecognizerTests: XCTestCase {

    private func createNormalizedEmbedding() -> [Float] {
        var embedding = [Float](repeating: 1.0, count: EmbeddingGallery.defaultDimension)
        _ = normalizeInPlace(&embedding)
        return embedding
    }

    func testRecognizeEmptyGallery() {
        let gallery = EmbeddingGallery()
        let recognizer = FaceRecognizer(gallery: gallery)

        let query = createNormalizedEmbedding()
        let result = recognizer.recognize(query: query)

        if case .unknown(let reason, _) = result {
            XCTAssertEqual(reason, .emptyGallery)
        } else {
            XCTFail("Should be empty gallery")
        }
    }

    func testRecognizeKnown() {
        let gallery = EmbeddingGallery()
        let emb = createNormalizedEmbedding()
        gallery.put(staffId: "123", embeddings: [emb])

        let recognizer = FaceRecognizer(gallery: gallery, config: RecognizerConfig(threshold: 0.5))

        let result = recognizer.recognize(query: emb)

        if case .known(let staffId, let similarity, _) = result {
            XCTAssertEqual(staffId, "123")
            XCTAssertEqual(similarity, 1.0, accuracy: 0.0001)
        } else {
            XCTFail("Should be known")
        }
    }
}
