import Foundation
import CoreGraphics
import Accelerate
import VideoToolbox

#if canImport(TensorFlowLite)
import TensorFlowLite

public class FaceEmbeddingEngine {
    private let interpreter: Interpreter

    private static let inputSize = 112
    private static let embeddingSize = 192
    private static let modelBatchSize = 2

    public init() throws {
        let resourceBundle: Bundle
        #if SWIFT_PACKAGE
        resourceBundle = Bundle.module
        #else
        let bundleURL = Bundle(for: type(of: self)).url(forResource: "ReskoolerFaceSDK_Models", withExtension: "bundle")
        resourceBundle = bundleURL.flatMap { Bundle(url: $0) } ?? Bundle(for: type(of: self))
        #endif

        guard let modelPath = resourceBundle.path(forResource: "MobileFaceNet", ofType: "tflite") else {
            throw NSError(domain: "FaceEmbeddingEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "MobileFaceNet.tflite not found"])
        }

        var options = Interpreter.Options()
        options.threadCount = 4

        self.interpreter = try Interpreter(modelPath: modelPath, options: options)
        try self.interpreter.allocateTensors()
    }

    public func getEmbedding(pixelBuffer: CVPixelBuffer) throws -> [Float] {
        var rgbData = try prepareInputData(pixelBuffer: pixelBuffer)
        let tensorData = Data(buffer: UnsafeBufferPointer(start: &rgbData, count: rgbData.count))

        try interpreter.copy(tensorData, toInputAt: 0)
        try interpreter.invoke()

        let outputTensor = try interpreter.output(at: 0)
        let outputSize = FaceEmbeddingEngine.embeddingSize

        var outputArray = [Float](repeating: 0, count: outputSize)
        _ = outputArray.withUnsafeMutableBytes { outputTensor.data.copyBytes(to: $0) }

        l2Normalize(&outputArray)

        return outputArray
    }

    private func prepareInputData(pixelBuffer: CVPixelBuffer) throws -> [Float] {
        let width = FaceEmbeddingEngine.inputSize
        let height = FaceEmbeddingEngine.inputSize
        let batchSize = FaceEmbeddingEngine.modelBatchSize
        let channels = 3

        var data = [Float](repeating: 0, count: width * height * channels * batchSize)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw NSError(domain: "FaceEmbeddingEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot access pixel buffer"])
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        var offset = 0
        for _ in 0..<batchSize {
            for y in 0..<height {
                for x in 0..<width {
                    let pixelIndex = y * bytesPerRow + x * 4
                    let bVal = Float(buffer[pixelIndex])
                    let gVal = Float(buffer[pixelIndex + 1])
                    let rVal = Float(buffer[pixelIndex + 2])

                    data[offset] = (rVal / 127.5) - 1.0
                    data[offset + 1] = (gVal / 127.5) - 1.0
                    data[offset + 2] = (bVal / 127.5) - 1.0

                    offset += 3
                }
            }
        }

        return data
    }

    private func l2Normalize(_ embedding: inout [Float]) {
        var sum: Double = 0.0
        for value in embedding {
            sum += Double(value) * Double(value)
        }

        let norm = Float(sqrt(sum))
        if norm <= 0.000001 { return }

        for i in 0..<embedding.count {
            embedding[i] /= norm
        }
    }
}
#endif
