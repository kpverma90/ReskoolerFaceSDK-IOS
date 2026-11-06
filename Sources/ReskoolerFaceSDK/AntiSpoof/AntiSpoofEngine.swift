import Foundation
import CoreGraphics
import CoreVideo
import TensorFlowLite

public struct TrackState {
    public var liveFrameCount: Int = 0
    public var history: [Float] = []

    public mutating func clear() {
        liveFrameCount = 0
        history.removeAll()
    }
}

public class AntiSpoofEngine {
    private let interpreter27: Interpreter
    private let interpreter40: Interpreter

    private static let inputSize = 256
    private static let classCount = 3
    private static let minHistorySamples = 3

    private var tracks: [Int: TrackState] = [:]

    public init() throws {
        guard let model27Path = Bundle(for: type(of: self)).path(forResource: "model_2_7", ofType: "tflite"),
              let model40Path = Bundle(for: type(of: self)).path(forResource: "model_4_0", ofType: "tflite") else {
            throw NSError(domain: "AntiSpoofEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Models not found"])
        }

        var options = Interpreter.Options()
        options.threadCount = 2

        self.interpreter27 = try Interpreter(modelPath: model27Path, options: options)
        self.interpreter40 = try Interpreter(modelPath: model40Path, options: options)

        try self.interpreter27.allocateTensors()
        try self.interpreter40.allocateTensors()
    }

    public func checkLiveness(pixelBuffer: CVPixelBuffer, trackId: Int) throws -> Float {
        var state = tracks[trackId] ?? TrackState()

        // 1. Run inference on both models
        let score27 = try runModel(interpreter: interpreter27, pixelBuffer: pixelBuffer)
        let score40 = try runModel(interpreter: interpreter40, pixelBuffer: pixelBuffer)

        // Combine probabilities (heuristic mimicking Android threshold integration)
        let liveScore = (score27[1] + score40[1]) / 2.0 // C1 is typical live class index

        state.history.append(liveScore)
        if state.history.count > 10 {
            state.history.removeFirst()
        }

        if liveScore > 0.85 {
            state.liveFrameCount += 1
        }

        tracks[trackId] = state

        return state.liveFrameCount >= AntiSpoofEngine.minHistorySamples ? liveScore : 0.0
    }

    private func runModel(interpreter: Interpreter, pixelBuffer: CVPixelBuffer) throws -> [Float] {
        var rgbData = try prepareInputData(pixelBuffer: pixelBuffer)
        let tensorData = Data(buffer: UnsafeBufferPointer(start: &rgbData, count: rgbData.count))

        try interpreter.copy(tensorData, toInputAt: 0)
        try interpreter.invoke()

        let outputTensor = try interpreter.output(at: 0)
        var logits = [Float](repeating: 0, count: AntiSpoofEngine.classCount)
        _ = logits.withUnsafeMutableBytes { outputTensor.data.copyBytes(to: $0) }

        return softmax(logits: logits)
    }

    private func prepareInputData(pixelBuffer: CVPixelBuffer) throws -> [Float] {
        let width = AntiSpoofEngine.inputSize
        let height = AntiSpoofEngine.inputSize
        var data = [Float](repeating: 0, count: width * height * 3)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw NSError(domain: "AntiSpoof", code: 2, userInfo: [NSLocalizedDescriptionKey: "No buffer"])
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        var offset = 0
        for y in 0..<height {
            for x in 0..<width {
                let p = y * bytesPerRow + x * 4
                let b = Float(buffer[p])
                let g = Float(buffer[p+1])
                let r = Float(buffer[p+2])

                // Models expect BGR order in float representation without division for AntiSpoof in this arch.
                data[offset] = b
                data[offset+1] = g
                data[offset+2] = r
                offset += 3
            }
        }
        return data
    }

    private func softmax(logits: [Float]) -> [Float] {
        let maxLogit = logits.max() ?? 0
        let exps = logits.map { exp($0 - maxLogit) }
        let sum = exps.reduce(0, +)
        return sum > 0 ? exps.map { $0 / sum } : logits
    }

    public func reset(trackId: Int) {
        tracks[trackId]?.clear()
    }

    public func retainOnly(activeKeys: Set<Int>) {
        tracks = tracks.filter { activeKeys.contains($0.key) }
    }

    public func close() {
        tracks.removeAll()
    }
}
