# iOS Implementation Plan

## Phase 1: Setup and Structure
- Ensure `feature/ios-native-sdk` branch is checked out.
- Initialize Swift Package Structure:
  - Create package `ReskoolerFaceSDK`
  - Define folder structure under `Sources/ReskoolerFaceSDK/`
- Add dependencies (`TensorFlowLiteSwift`, `GoogleMLKit/FaceDetection`).

## Phase 2: Copy Models
- Move `.tflite` files (`MobileFaceNet.tflite`, `model_2_7.tflite`, `model_4_0.tflite`) to `Sources/ReskoolerFaceSDK/Resources/Models`.

## Phase 3: Implement Utility Classes
- `FaceMetrics.swift` and `FaceQualityGate.swift` for quality assessment.
- Image processing helpers (`ImageProcessor.swift`) for cropping, resizing, and pixel extraction using vImage / CoreImage.

## Phase 4: Integrate ML Kit Face Detection
- Create `FaceDetectorEngine.swift` that uses ML Kit Face Detection for iOS.
- Handle frame orientation from `CMSampleBuffer`.

## Phase 5: Implement TFLite Processing
- Create `FaceEmbeddingEngine.swift` using `TensorFlowLiteSwift`.
- Setup normalization logic, buffer passing, model loading from bundle.
- Create `AntiSpoofEngine.swift` implementing the liveness temporal tracking.

## Phase 6: Core Logic Implementation
- `FaceRecognizer.swift` and `EmbeddingGallery.swift` logic.
- `KioskSession.swift`, `SelfAttendanceSession.swift`, `KioskWatchdog.swift`.
- Root `FaceSDK.swift` coordinator interface.

## Phase 7: Camera and Exposure Integration
- `CameraManager.swift` using `AVCaptureSession`.
- Setup Expo Module wrapper if applicable in this repo or document integration steps for Expo.
