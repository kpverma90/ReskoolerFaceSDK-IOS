
import Foundation
import AVFoundation
import CoreVideo

#if os(iOS)
#if canImport(MLKitVision) && canImport(MLKitFaceDetection)

import MLKitVision
import MLKitFaceDetection

public class FaceSDK {

    // MARK: - Core Components

    private let config: FaceSdkConfig

    private let cameraManager = CameraManager()
    private let faceDetectorEngine = FaceDetectorEngine()
    private let gallery = EmbeddingGallery()

    private let antiSpoofEngine: AntiSpoofEngine?
    private let embeddingEngine: FaceEmbeddingEngine?

    private let qualityGate: FaceQualityGate
    private let trackSession = TrackSession()
    private let recognizer: FaceRecognizer

    private var kiosk: KioskSession?
    private var attendance: SelfAttendanceSession?

    private let watchdog = KioskWatchdog()

    private let processingQueue = DispatchQueue(
        label: "com.reskooler.FaceSDKProcessingQueue",
        qos: .userInitiated
    )

    private let stateLock = NSLock()

    private var _isProcessingFrame = false

    private var isProcessingFrame: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _isProcessingFrame
        }
        set {
            stateLock.lock()
            _isProcessingFrame = newValue
            stateLock.unlock()
        }
    }

    private var mode: FaceSdkMode = .kiosk
    private var isReleased = false

    // MARK: - Events

    public var onResult: ((FaceSdkResult) -> Void)?

    // MARK: - Camera Properties

    public var previewSession: AVCaptureSession? {
        cameraManager.previewSession
    }

    public var isFrontCamera: Bool {
        cameraManager.currentPosition == .front
    }

    public var isCameraRunning: Bool {
        cameraManager.isRunning
    }

    // MARK: - Initializer

    public init(config: FaceSdkConfig = FaceSdkConfig()) {

        self.config = config

        self.recognizer = FaceRecognizer(
            gallery: gallery,
            config: RecognizerConfig(
                threshold: config.matchThreshold
            )
        )

        self.qualityGate = FaceQualityGate()

        self.antiSpoofEngine = try? AntiSpoofEngine()
        self.embeddingEngine = try? FaceEmbeddingEngine()

        setupCamera()
    }

    // MARK: - Camera Setup

    private func setupCamera() {

        cameraManager.onFrame = { [weak self] buffer in

            guard let self else { return }

            self.processFrame(buffer)
        }

        cameraManager.onError = { [weak self] error in

            guard let self else { return }

            self.emit(
                FaceSdkResult(
                    type: .error,
                    message: error
                )
            )
        }
    }

    // MARK: - Start SDK

    public func start(mode: FaceSdkMode) {

        guard !isReleased else {

            emit(
                FaceSdkResult(
                    type: .error,
                    message: "Face SDK has been released"
                )
            )

            return
        }

        self.mode = mode

        switch mode {

        case .kiosk:

            kiosk = KioskSession(
                recognizer: recognizer
            )

            attendance = nil

        case .selfAttendance:

            attendance = SelfAttendanceSession(
                recognizer: recognizer
            )

            kiosk = nil

        case .enrollment:

            kiosk = nil
            attendance = nil

            emit(
                FaceSdkResult(
                    type: .error,
                    message: "Enrollment capture is not implemented in this SDK version"
                )
            )

            return
        }

        cameraManager.startCamera()
    }

    // MARK: - Stop SDK

    public func stop() {

        cameraManager.stopCamera()

        isProcessingFrame = false
    }

    // MARK: - Switch Camera

    @discardableResult
    public func switchCamera() -> Bool {

        guard !isReleased else {
            return false
        }

        return cameraManager.switchCamera()
    }

    // MARK: - Process Camera Frame

    private func processFrame(_ sampleBuffer: CMSampleBuffer) {

        guard !isReleased else {
            return
        }

        guard !isProcessingFrame else {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        isProcessingFrame = true

        watchdog.onFrameReceived()
        watchdog.onFrameStarted()

        let visionImage = VisionImage(buffer: sampleBuffer)
        visionImage.orientation = .up

        let frameWidth = CVPixelBufferGetWidth(pixelBuffer)
        let frameHeight = CVPixelBufferGetHeight(pixelBuffer)

        faceDetectorEngine.process(
            image: visionImage,
            onSuccess: { [weak self] faces in

                guard let self else {
                    return
                }

                guard !self.isReleased else {

                    self.finishProcessing(success: false)
                    return
                }

                self.handleDetectedFaces(
                    faces,
                    pixelBuffer: pixelBuffer,
                    frameWidth: frameWidth,
                    frameHeight: frameHeight
                )
            },
            onFailure: { [weak self] error in

                guard let self else {
                    return
                }

                self.emit(
                    FaceSdkResult(
                        type: .error,
                        message: error.localizedDescription
                    )
                )

                self.finishProcessing(success: false)
            }
        )
    }

    // MARK: - Handle Detected Faces

    private func handleDetectedFaces(
        _ faces: [Face],
        pixelBuffer: CVPixelBuffer,
        frameWidth: Int,
        frameHeight: Int
    ) {

        // No face detected

        if faces.isEmpty {

            if mode == .selfAttendance {

                _ = attendance?.processFrame(
                    frame: AttendanceFrame(
                        faceCount: 0,
                        quality: nil,
                        isLive: false,
                        liveScore: 0,
                        embedding: nil
                    )
                )
            }

            emit(
                FaceSdkResult(
                    type: .noFace
                )
            )

            finishProcessing(success: true)
            return
        }

        // Multiple faces detected

        if faces.count > 1 {

            emit(
                FaceSdkResult(
                    type: .multipleFaces
                )
            )

            finishProcessing(success: true)
            return
        }

        guard let face = faces.first else {

            finishProcessing(success: false)
            return
        }

        let trackId = face.trackingID > 0
            ? Int(face.trackingID)
            : -1

        if trackSession.onFace(trackingId: trackId) {

            antiSpoofEngine?.reset(
                trackId: trackId
            )
        }

        antiSpoofEngine?.retainOnly(
            activeKeys: [trackId]
        )

        // Face quality metrics

        let metrics = FaceMetrics(
            left: Float(face.frame.minX),
            top: Float(face.frame.minY),
            right: Float(face.frame.maxX),
            bottom: Float(face.frame.maxY),
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            yaw: Float(face.headEulerAngleY),
            pitch: Float(face.headEulerAngleX),
            roll: Float(face.headEulerAngleZ)
        )

        let quality = qualityGate.evaluate(
            m: metrics
        )

        // Heavy processing

        processingQueue.async { [weak self] in

            guard let self else {
                return
            }

            guard !self.isReleased else {

                self.finishProcessing(success: false)
                return
            }

            self.processFace(
                face: face,
                pixelBuffer: pixelBuffer,
                quality: quality,
                trackId: trackId
            )
        }
    }

    // MARK: - Face Processing

    private func processFace(
        face: Face,
        pixelBuffer: CVPixelBuffer,
        quality: QualityResult,
        trackId: Int
    ) {

        var isLive = false
        var liveScore: Float = 0
        var embedding: [Float]?

        do {

            if case .ok = quality {

                // Liveness processing

                if let cropped = ImageProcessor.cropAndResize(
                    pixelBuffer: pixelBuffer,
                    faceRect: face.frame,
                    targetSize: 256
                ) {

                    liveScore = try antiSpoofEngine?
                        .checkLiveness(
                            pixelBuffer: cropped,
                            trackId: trackId
                        ) ?? 0

                    isLive = liveScore >= 0.85
                }

                // Face embedding

                if isLive {

                    if let embeddingCrop = ImageProcessor.cropAndResize(
                        pixelBuffer: pixelBuffer,
                        faceRect: face.frame,
                        targetSize: 112
                    ) {

                        embedding = try embeddingEngine?
                            .getEmbedding(
                                pixelBuffer: embeddingCrop
                            )
                    }
                }
            }

            // Kiosk Mode

            switch mode {

            case .kiosk:

                processKioskFrame(
                    quality: quality,
                    isLive: isLive,
                    liveScore: liveScore,
                    embedding: embedding,
                    trackId: trackId
                )

            case .selfAttendance:

                processAttendanceFrame(
                    quality: quality,
                    isLive: isLive,
                    liveScore: liveScore,
                    embedding: embedding
                )

            case .enrollment:

                emit(
                    FaceSdkResult(
                        type: .error,
                        message: "Enrollment capture is not implemented"
                    )
                )
            }

            finishProcessing(success: true)

        } catch {

            emit(
                FaceSdkResult(
                    type: .error,
                    message: error.localizedDescription
                )
            )

            finishProcessing(success: false)
        }
    }

    // MARK: - Kiosk Processing

    private func processKioskFrame(
        quality: QualityResult,
        isLive: Bool,
        liveScore: Float,
        embedding: [Float]?,
        trackId: Int
    ) {

        let observation = KioskObservation(
            trackId: trackId,
            quality: quality,
            isLive: isLive,
            liveScore: liveScore,
            embedding: embedding
        )

        guard let events = kiosk?.processFrame(
            observations: [observation]
        ) else {
            return
        }

        for event in events {

            switch event {

            case .matched(let staffId):

                emit(
                    FaceSdkResult(
                        type: .matched,
                        staffId: staffId,
                        trackId: trackId
                    )
                )

            case .spoof(let reason):

                emit(
                    FaceSdkResult(
                        type: .spoofSuspected,
                        message: reason,
                        trackId: trackId
                    )
                )
            }
        }
    }

    // MARK: - Self Attendance Processing

    private func processAttendanceFrame(
        quality: QualityResult,
        isLive: Bool,
        liveScore: Float,
        embedding: [Float]?
    ) {

        let frame = AttendanceFrame(
            faceCount: 1,
            quality: quality,
            isLive: isLive,
            liveScore: liveScore,
            embedding: embedding
        )

        if let result = attendance?.processFrame(
            frame: frame
        ) {

            emit(result)
        }
    }

    // MARK: - Gallery Management

    public func setGallery(
        embeddings: [String: [[Float]]]
    ) {

        guard !isReleased else {
            return
        }

        gallery.replaceAll(
            staff: embeddings
        )
    }

    public func setStaffEmbeddings(
        staffId: String,
        embeddings: [[Float]]
    ) {

        guard !isReleased else {
            return
        }

        gallery.put(
            staffId: staffId,
            embeddings: embeddings
        )
    }

    public func removeStaff(
        staffId: String
    ) {

        guard !isReleased else {
            return
        }

        gallery.remove(
            staffId: staffId
        )
    }

    public func clearGallery() {

        guard !isReleased else {
            return
        }

        gallery.clear()
    }

    public func getGallery() -> [String: [[Float]]] {

        return gallery.entries()
    }

    public var staffCount: Int {
        gallery.staffCount
    }

    // MARK: - Processing Completion

    private func finishProcessing(success: Bool) {

        watchdog.onFrameFinished(
            success: success
        )

        isProcessingFrame = false
    }

    // MARK: - Emit Result

    private func emit(_ result: FaceSdkResult) {

        DispatchQueue.main.async { [weak self] in

            guard let self else {
                return
            }

            guard !self.isReleased else {
                return
            }

            self.onResult?(result)
        }
    }

    // MARK: - Release SDK

    public func close() {

        guard !isReleased else {
            return
        }

        isReleased = true

        stop()

        cameraManager.onFrame = nil
        cameraManager.onError = nil

        onResult = nil

        antiSpoofEngine?.close()

        kiosk = nil
        attendance = nil
    }

    deinit {
        close()
    }
}

#endif
#endif
