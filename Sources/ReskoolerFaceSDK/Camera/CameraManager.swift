
import Foundation
import AVFoundation

#if os(iOS)

public final class CameraManager: NSObject {

    // MARK: - Camera Session

    private var captureSession: AVCaptureSession?

    /// Used by AVCaptureVideoPreviewLayer to display the camera preview.
    public var previewSession: AVCaptureSession? {
        sessionQueue.sync {
            captureSession
        }
    }

    private let videoOutput = AVCaptureVideoDataOutput()

    private let sessionQueue = DispatchQueue(
        label: "com.reskooler.CameraManager.SessionQueue"
    )

    private let frameQueue = DispatchQueue(
        label: "com.reskooler.CameraManager.FrameQueue"
    )

    private var currentInput: AVCaptureDeviceInput?
    private var currentCameraPosition: AVCaptureDevice.Position = .front

    public var currentPosition: AVCaptureDevice.Position {
        sessionQueue.sync {
            currentCameraPosition
        }
    }

    public var onError: ((String) -> Void)?
    public var onFrame: ((CMSampleBuffer) -> Void)?

    public override init() {
        super.init()
    }

    // MARK: - Start Camera

    public func startCamera() {
        startCamera(position: .front)
    }

    public func startCamera(position: AVCaptureDevice.Position) {

        sessionQueue.sync {

            if captureSession != nil {
                return
            }

            let session = AVCaptureSession()
            session.sessionPreset = .vga640x480

            guard let camera = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: position
            ) else {
                onError?("Camera not found")
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: camera)

                guard session.canAddInput(input) else {
                    onError?("Cannot add camera input")
                    return
                }

                session.addInput(input)

                videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String:
                        Int(kCVPixelFormatType_32BGRA)
                ]

                videoOutput.alwaysDiscardsLateVideoFrames = true

                videoOutput.setSampleBufferDelegate(
                    self,
                    queue: frameQueue
                )

                guard session.canAddOutput(videoOutput) else {
                    videoOutput.setSampleBufferDelegate(nil, queue: nil)
                    onError?("Cannot add video output")
                    return
                }

                session.addOutput(videoOutput)

                if let connection = videoOutput.connection(with: .video) {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }

                    if connection.isVideoMirroringSupported {
                        connection.isVideoMirrored = false
                    }
                }

                currentInput = input
                currentCameraPosition = position
                captureSession = session

                session.startRunning()

            } catch {
                onError?(
                    "Camera error: \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - Switch Camera

    @discardableResult
    public func switchCamera() -> Bool {

        return sessionQueue.sync {

            guard let session = captureSession else {
                onError?("Camera is not running")
                return false
            }

            let newPosition: AVCaptureDevice.Position =
                currentCameraPosition == .front ? .back : .front

            guard let newCamera = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: newPosition
            ) else {
                onError?("Requested camera not found")
                return false
            }

            do {
                let newInput = try AVCaptureDeviceInput(
                    device: newCamera
                )

                guard session.canAddInput(newInput) else {
                    onError?("Cannot switch camera input")
                    return false
                }

                session.beginConfiguration()

                if let oldInput = currentInput {
                    session.removeInput(oldInput)
                }

                if session.canAddInput(newInput) {

                    session.addInput(newInput)

                    currentInput = newInput
                    currentCameraPosition = newPosition

                    session.commitConfiguration()

                    return true

                } else {

                    if let oldInput = currentInput,
                       session.canAddInput(oldInput) {
                        session.addInput(oldInput)
                    }

                    session.commitConfiguration()

                    onError?("Failed to switch camera")
                    return false
                }

            } catch {
                onError?(
                    "Camera switch error: \(error.localizedDescription)"
                )
                return false
            }
        }
    }

    // MARK: - Stop Camera

    public func stopCamera() {

        sessionQueue.sync {

            guard let session = captureSession else {
                return
            }

            session.stopRunning()

            videoOutput.setSampleBufferDelegate(nil, queue: nil)

            if let input = currentInput {
                session.removeInput(input)
            }

            if session.outputs.contains(videoOutput) {
                session.removeOutput(videoOutput)
            }

            currentInput = nil
            captureSession = nil
        }
    }

    // MARK: - Camera State

    public var isRunning: Bool {
        sessionQueue.sync {
            captureSession?.isRunning ?? false
        }
    }
}

// MARK: - Video Frame Delegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onFrame?(sampleBuffer)
    }
}

#endif