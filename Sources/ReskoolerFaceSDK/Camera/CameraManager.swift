import Foundation
import AVFoundation

public class CameraManager: NSObject {
    private var captureSession: AVCaptureSession?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.reskooler.CameraManagerQueue")

    public var onError: ((String) -> Void)?
    public var onFrame: ((CMSampleBuffer) -> Void)?

    public override init() {
        super.init()
    }

    public func startCamera() {
        let session = AVCaptureSession()
        session.sessionPreset = .vga640x480

        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            onError?("Front camera not found")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: frontCamera)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                onError?("Cannot add camera input")
                return
            }

            videoOutput.setSampleBufferDelegate(self, queue: queue)
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]

            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
                if let connection = videoOutput.connection(with: .video) {
                    connection.videoOrientation = .portrait
                    connection.isVideoMirrored = false // Fix coordinate mismatch; flipped orientation is sufficient for MLKit
                }
            } else {
                onError?("Cannot add video output")
                return
            }

            self.captureSession = session
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        } catch {
            onError?("Camera error: \(error.localizedDescription)")
        }
    }

    public func stopCamera() {
        captureSession?.stopRunning()
        captureSession = nil
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onFrame?(sampleBuffer)
    }
}
