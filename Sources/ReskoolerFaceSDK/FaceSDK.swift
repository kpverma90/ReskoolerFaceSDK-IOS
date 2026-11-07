import Foundation
import AVFoundation

#if os(iOS)

#if canImport(MLKitVision) && canImport(MLKitFaceDetection)
import MLKitVision
import MLKitFaceDetection

public class FaceSDK {
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
    private var enrollmentSession: EnrollmentSession?
    private let watchdog = KioskWatchdog()

    private let processingQueue = DispatchQueue(label: "com.reskooler.FaceSDKProcessingQueue", qos: .userInitiated)
    private let stateLock = NSLock()
    private var _isProcessingFrame = false

    private var isProcessingFrame: Bool {
        get {
            stateLock.lock()
            let value = _isProcessingFrame
            stateLock.unlock()
            return value
        }
        set {
            stateLock.lock()
            _isProcessingFrame = newValue
            stateLock.unlock()
        }
    }

    private var mode: FaceSdkMode?
    private var isReleased = false

    public var onResult: ((FaceSdkResult) -> Void)?

    public init(config: FaceSdkConfig = FaceSdkConfig()) {
        self.config = config
        self.recognizer = FaceRecognizer(gallery: gallery, config: RecognizerConfig(threshold: config.matchThreshold))
        self.qualityGate = FaceQualityGate()
        self.antiSpoofEngine = try? AntiSpoofEngine()
        self.embeddingEngine = try? FaceEmbeddingEngine()

        setupCamera()
    }

    private func setupCamera() {
        cameraManager.onFrame = { [weak self] buffer in
            self?.processFrame(buffer)
        }
        cameraManager.onError = { [weak self] error in
            self?.onResult?(FaceSdkResult(type: .error, message: error))
        }
    }

    public func startEnrollment(staffId: String) {
        self.mode = .enrollment
        self.enrollmentSession = EnrollmentSession(staffId: staffId, poses: config.enrollmentPoses, gallery: gallery)
        cameraManager.startCamera()
    }

    public func startSelfAttendance() {
        self.mode = .selfAttendance
        self.attendance = SelfAttendanceSession(recognizer: recognizer)
        cameraManager.startCamera()
    }

    public func startKiosk() {
        self.mode = .kiosk
        self.kiosk = KioskSession(recognizer: recognizer)
        cameraManager.startCamera()
    }

    public func stop() {
        cameraManager.stopCamera()
    }

    private func processFrame(_ sampleBuffer: CMSampleBuffer) {
        watchdog.onFrameReceived()
        guard !isReleased, !isProcessingFrame else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        isProcessingFrame = true
        watchdog.onFrameStarted()

        let visionImage = VisionImage(buffer: sampleBuffer)
        visionImage.orientation = .up

        let frameW = CVPixelBufferGetWidth(pixelBuffer)
        let frameH = CVPixelBufferGetHeight(pixelBuffer)

        faceDetectorEngine.process(image: visionImage, onSuccess: { [weak self] faces in
            guard let self = self else {
                return
            }

            if faces.isEmpty {
                if self.mode == .selfAttendance {
                    _ = self.attendance?.processFrame(frame: AttendanceFrame(faceCount: 0, quality: nil, isLive: false, liveScore: 0, embedding: nil))
                    self.onResult?(FaceSdkResult(type: .noFace))
                } else if self.mode == .enrollment {
                    let update = self.enrollmentSession?.onFrame(frame: EnrollmentFrame(faceCount: 0, quality: nil, yaw: 0, isLive: false, embedding: nil))
                    self.handleEnrollmentUpdate(update)
                } else {
                    self.onResult?(FaceSdkResult(type: .noFace))
                }
                self.finishProcessing(success: true)
                return
            }
            if faces.count > 1 {
                if self.mode == .enrollment {
                    let update = self.enrollmentSession?.onFrame(frame: EnrollmentFrame(faceCount: faces.count, quality: nil, yaw: 0, isLive: false, embedding: nil))
                    self.handleEnrollmentUpdate(update)
                } else {
                    self.onResult?(FaceSdkResult(type: .multipleFaces))
                }
                self.finishProcessing(success: true)
                return
            }

            let face = faces[0]
            let trackId = face.trackingID > 0 ? Int(face.trackingID) : -1

            if self.trackSession.onFace(trackingId: trackId) {
                self.antiSpoofEngine?.reset(trackId: trackId)
            }
            self.antiSpoofEngine?.retainOnly(activeKeys: [trackId])

            let metrics = FaceMetrics(
                left: Float(face.frame.minX), top: Float(face.frame.minY),
                right: Float(face.frame.maxX), bottom: Float(face.frame.maxY),
                frameWidth: frameW, frameHeight: frameH,
                yaw: Float(face.headEulerAngleY),
                pitch: Float(face.headEulerAngleX),
                roll: Float(face.headEulerAngleZ)
            )

            let quality = self.qualityGate.evaluate(m: metrics)

            self.processingQueue.async { [weak self] in
                guard let self = self else {
                    return
                }

                var isLive = false
                var liveScore: Float = 0.0
                var embedding: [Float]? = nil

                do {
                    if case .ok = quality {
                        if let cropped = ImageProcessor.cropAndResize(pixelBuffer: pixelBuffer, faceRect: face.frame, targetSize: 256) {
                            liveScore = try self.antiSpoofEngine?.checkLiveness(pixelBuffer: cropped, trackId: trackId) ?? 0.0
                            isLive = liveScore >= 0.85
                        }

                        if isLive {
                            if let embCropped = ImageProcessor.cropAndResize(pixelBuffer: pixelBuffer, faceRect: face.frame, targetSize: 112) {
                                embedding = try self.embeddingEngine?.getEmbedding(pixelBuffer: embCropped)
                            }
                        }
                    }

                    if self.mode == .kiosk {
                        let obs = KioskObservation(trackId: trackId, quality: quality, isLive: isLive, liveScore: liveScore, embedding: embedding)
                        if let kEvents = self.kiosk?.processFrame(observations: [obs]) {
                            for ev in kEvents {
                                switch ev {
                                case .matched(let staffId):
                                    self.onResult?(FaceSdkResult(type: .matched, staffId: staffId, trackId: trackId))
                                case .spoof(let reason):
                                    self.onResult?(FaceSdkResult(type: .spoofSuspected, message: reason, trackId: trackId))
                                }
                            }
                        }
                    } else if self.mode == .selfAttendance {
                        let frame = AttendanceFrame(faceCount: 1, quality: quality, isLive: isLive, liveScore: liveScore, embedding: embedding)
                        if let res = self.attendance?.processFrame(frame: frame) {
                            self.onResult?(res)
                        }
                    } else if self.mode == .enrollment {
                        let yaw = Float(face.headEulerAngleY)
                        let frame = EnrollmentFrame(faceCount: 1, quality: quality, yaw: yaw, isLive: isLive, embedding: embedding)
                        let update = self.enrollmentSession?.onFrame(frame: frame)
                        self.handleEnrollmentUpdate(update)
                    }

                    self.finishProcessing(success: true)
                } catch {
                    self.onResult?(FaceSdkResult(type: .error, message: error.localizedDescription))
                    self.finishProcessing(success: false)
                }
            }

        }, onFailure: { [weak self] error in
            self?.onResult?(FaceSdkResult(type: .error, message: error.localizedDescription))

            self?.stateLock.lock()
            self?._isProcessingFrame = false
            self?.stateLock.unlock()

            self?.watchdog.onFrameFinished(success: false)
        })
    }

    private func finishProcessing(success: Bool) {
        watchdog.onFrameFinished(success: success)
        isProcessingFrame = false
    }

    private func handleEnrollmentUpdate(_ update: EnrollmentUpdate?) {
        guard let update = update else { return }
        switch update {
        case .guidance(let pose, let reason, let message):
            let type: FaceSdkResultType
            switch reason {
            case .noFace: type = .noFace
            case .multipleFaces: type = .multipleFaces
            case .lowQuality, .inconsistentFace: type = .lowQuality
            case .invalidEmbedding: type = .error
            case .wrongPose, .holdStill, .checkingLiveness: type = .scanning
            }
            self.onResult?(FaceSdkResult(type: type, pose: pose, message: message))
        case .captured(let pose, _, let message):
            self.onResult?(FaceSdkResult(type: .success, pose: pose, message: message))
        case .completed(let result, let message):
            self.onResult?(FaceSdkResult(type: .success, staffId: result.staffId, enrollmentEmbeddings: result.embeddings, message: message))
        case .failed(_, let message):
            self.onResult?(FaceSdkResult(type: .error, message: message))
        case .inactive:
            break
        }
    }

    public func setGallery(embeddings: [String: [[Float]]]) {
        gallery.replaceAll(staff: embeddings)
    }

    public func close() {
        isReleased = true
        stop()
        antiSpoofEngine?.close()
    }
}
#endif
#endif
