
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
    private var enrollment: EnrollmentSession?

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

    // MARK: - Start Kiosk / Attendance

    public func start(mode: FaceSdkMode) {

        guard !isReleased else {
            emitError("Face SDK has been released")
            return
        }

        switch mode {

        case .kiosk:
            self.mode = .kiosk

            kiosk = KioskSession(
                recognizer: recognizer
            )

            attendance = nil
            enrollment = nil

        case .selfAttendance:
            self.mode = .selfAttendance

            attendance = SelfAttendanceSession(
                recognizer: recognizer
            )

            kiosk = nil
            enrollment = nil

        case .enrollment:
            emitError(
                "Use startEnrollment(staffId:) to start enrollment"
            )
            return
        }

        cameraManager.startCamera()
    }

    // MARK: - Start Enrollment

    public func startEnrollment(staffId: String) {

        guard !isReleased else {
            emitError("Face SDK has been released")
            return
        }

        guard !staffId.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            emitError("Invalid staff ID")
            return
        }

        mode = .enrollment

        kiosk = nil
        attendance = nil

        enrollment = EnrollmentSession(
            staffId: staffId,
            gallery: gallery
        )

        emit(
            FaceSdkResult(
                type: .success,
                pose: .straight,
                message: "Look straight"
            )
        )

        cameraManager.startCamera()
    }

    // MARK: - Cancel Enrollment

    public func cancelEnrollment() {

        enrollment?.cancel()
        enrollment = nil

        emit(
            FaceSdkResult(
                type: .success,
                message: "Enrollment cancelled"
            )
        )
    }

    // MARK: - Stop SDK

    public func stop() {

        cameraManager.stopCamera()

        enrollment?.cancel()
        enrollment = nil

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

        guard !isReleased else { return }
        guard !isProcessingFrame else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(
            sampleBuffer
        ) else {
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

                guard let self else { return }

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

                guard let self else { return }

                self.emitError(error.localizedDescription)
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

        // No face

        if faces.isEmpty {

            if mode == .enrollment {

                handleEnrollmentFrame(
                    EnrollmentFrame(
                        faceCount: 0,
                        quality: nil,
                        yaw: 0,
                        isLive: false,
                        embedding: nil
                    )
                )

            } else if mode == .selfAttendance {

                if let result = attendance?.processFrame(
                    frame: AttendanceFrame(
                        faceCount: 0,
                        quality: nil,
                        isLive: false,
                        liveScore: 0,
                        embedding: nil
                    )
                ) {
                    emit(result)
                }

                emit(FaceSdkResult(type: .noFace))

            } else {

                emit(FaceSdkResult(type: .noFace))
            }

            finishProcessing(success: true)
            return
        }

        // Multiple faces

        if faces.count > 1 {

            if mode == .enrollment {

                handleEnrollmentFrame(
                    EnrollmentFrame(
                        faceCount: faces.count,
                        quality: nil,
                        yaw: 0,
                        isLive: false,
                        embedding: nil
                    )
                )

            } else {

                emit(
                    FaceSdkResult(
                        type: .multipleFaces
                    )
                )
            }

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

        let yaw = Float(face.headEulerAngleY)

        let metrics = FaceMetrics(
            left: Float(face.frame.minX),
            top: Float(face.frame.minY),
            right: Float(face.frame.maxX),
            bottom: Float(face.frame.maxY),
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            yaw: yaw,
            pitch: Float(face.headEulerAngleX),
            roll: Float(face.headEulerAngleZ)
        )

        let quality = qualityGate.evaluate(
            m: metrics
        )

        processingQueue.async { [weak self] in

            guard let self else { return }

            guard !self.isReleased else {
                self.finishProcessing(success: false)
                return
            }

            self.processFace(
                face: face,
                pixelBuffer: pixelBuffer,
                quality: quality,
                trackId: trackId,
                yaw: yaw
            )
        }
    }

    // MARK: - Face Processing

    private func processFace(
        face: Face,
        pixelBuffer: CVPixelBuffer,
        quality: QualityResult,
        trackId: Int,
        yaw: Float
    ) {

        var isLive = false
        var liveScore: Float = 0
        var embedding: [Float]?

        do {

            if case .ok = quality {

                // Liveness

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

                // Embedding

                if isLive {

                    let canCaptureEnrollmentPose: Bool

                    if mode == .enrollment {
                        canCaptureEnrollmentPose =
                            enrollment?.poseMatches(yaw: yaw) ?? false
                    } else {
                        canCaptureEnrollmentPose = true
                    }

                    if canCaptureEnrollmentPose {

                        if let embeddingCrop =
                            ImageProcessor.cropAndResize(
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
            }

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

                handleEnrollmentFrame(
                    EnrollmentFrame(
                        faceCount: 1,
                        quality: quality,
                        yaw: yaw,
                        isLive: isLive,
                        embedding: embedding
                    )
                )
            }

            finishProcessing(success: true)

        } catch {

            emitError(error.localizedDescription)
            finishProcessing(success: false)
        }
    }

    // MARK: - Enrollment Processing

    private func handleEnrollmentFrame(
        _ frame: EnrollmentFrame
    ) {

        guard let session = enrollment,
              session.isActive() else {
            return
        }

        let update = session.onFrame(frame)

        handleEnrollmentUpdate(update)
    }

    // MARK: - Enrollment Updates

    private func handleEnrollmentUpdate(
        _ update: EnrollmentUpdate
    ) {

        switch update {

        case .inactive:
            break

        case .guidance(let pose, let reason, let message):

            let resultType: FaceSdkResultType

            switch reason {

            case .noFace:
                resultType = .noFace

            case .multipleFaces:
                resultType = .multipleFaces

            case .lowQuality:
                resultType = .lowQuality

            case .invalidEmbedding:
                resultType = .error

            case .wrongPose,
                 .checkingLiveness,
                 .holdStill,
                 .inconsistentFace:
                resultType = .scanning
            }

            emit(
                FaceSdkResult(
                    type: resultType,
                    pose: pose,
                    message: message
                )
            )

        case .captured(_, let next, let message):

            emit(
                FaceSdkResult(
                    type: .success,
                    pose: next,
                    message: message
                )
            )

        case .completed(let result):

            // Save all three embeddings in gallery

            gallery.put(
                staffId: result.staffId,
                embeddings: result.embeddings
            )

            emit(
                FaceSdkResult(
                    type: .success,
                    staffId: result.staffId,
                    enrollmentEmbeddings: result.embeddings,
                    pose: .right,
                    message: "Enrollment completed"
                )
            )

            enrollment = nil
            kiosk?.clearTracks()

        case .failed(_, let message):

            emit(
                FaceSdkResult(
                    type: .error,
                    message: message
                )
            )

            enrollment = nil
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

        guard !isReleased else { return }

        gallery.replaceAll(
            staff: embeddings
        )
    }

    public func setStaffEmbeddings(
        staffId: String,
        embeddings: [[Float]]
    ) {

        guard !isReleased else { return }

        gallery.put(
            staffId: staffId,
            embeddings: embeddings
        )
    }

    public func removeStaff(
        staffId: String
    ) {

        guard !isReleased else { return }

        gallery.remove(
            staffId: staffId
        )
    }

    public func clearGallery() {

        guard !isReleased else { return }

        gallery.clear()
    }

    public func getGallery() -> [String: [[Float]]] {
        gallery.entries()
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

    // MARK: - Error

    private func emitError(_ message: String) {

        emit(
            FaceSdkResult(
                type: .error,
                message: message
            )
        )
    }

    // MARK: - Emit Result

    private func emit(_ result: FaceSdkResult) {

        DispatchQueue.main.async { [weak self] in

            guard let self else { return }
            guard !self.isReleased else { return }

            self.onResult?(result)
        }
    }

    // MARK: - Release SDK

    public func close() {

        guard !isReleased else { return }

        isReleased = true

        stop()

        cameraManager.onFrame = nil
        cameraManager.onError = nil

        onResult = nil

        antiSpoofEngine?.close()

        kiosk = nil
        attendance = nil
        enrollment = nil
    }

    deinit {
        close()
    }
}

#endif
#endif
