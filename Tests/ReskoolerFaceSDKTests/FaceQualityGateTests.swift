import XCTest
@testable import ReskoolerFaceSDK

final class FaceQualityGateTests: XCTestCase {
    func testValidFace() {
        let metrics = FaceMetrics(
            left: 50, top: 50, right: 150, bottom: 150,
            frameWidth: 640, frameHeight: 480,
            yaw: 0, pitch: 0, roll: 0
        )
        let gate = FaceQualityGate()

        let result = gate.evaluate(m: metrics)

        if case .ok = result {
            XCTAssertTrue(true)
        } else {
            XCTFail("Valid face was rejected")
        }
    }

    func testTooSmallFace() {
        let metrics = FaceMetrics(
            left: 50, top: 50, right: 60, bottom: 60, // 10x10 is too small for 640x480
            frameWidth: 640, frameHeight: 480,
            yaw: 0, pitch: 0, roll: 0
        )
        let gate = FaceQualityGate()

        let result = gate.evaluate(m: metrics)

        if case .rejected(let issue) = result {
            XCTAssertEqual(issue, .tooSmall)
        } else {
            XCTFail("Small face was not rejected")
        }
    }
}
