# Android to iOS Mapping

## Framework Replacements

| Feature | Android | iOS |
| --- | --- | --- |
| Camera | CameraX (Preview, ImageAnalysis) | AVFoundation (AVCaptureSession, AVCaptureVideoDataOutput) |
| Face Detection | ML Kit Face Detection | Vision framework (VNDetectFaceRectanglesRequest / ML Kit for iOS) |
| Models Runtime | TensorFlow Lite for Android | TensorFlowLiteSwift |
| Image Processing | Bitmap, Matrix, Canvas | Core Image, Accelerate (vImage), CVPixelBuffer |

## Component Mapping

| Android Class | iOS Equivalent |
| --- | --- |
| `CameraManager.kt` | `CameraManager.swift` |
| `FaceDetectorEngine.kt` | `FaceDetectorEngine.swift` |
| `FaceEmbeddingEngine.kt` | `FaceEmbeddingEngine.swift` |
| `AntiSpoofEngine.kt` | `AntiSpoofEngine.swift` |
| `FaceQualityGate.kt` | `FaceQualityGate.swift` |
| `FaceRecognizer.kt` | `FaceRecognizer.swift` |
| `EmbeddingGallery.kt` | `EmbeddingGallery.swift` |
| `KioskSession.kt` | `KioskSession.swift` |

## Data Formats & Transforms
- Android uses byte buffers mapped directly into TFLite. On iOS, we will use `Data` or directly copy memory from a CVPixelBuffer (after standardizing it to planar RGB or similar based on TFLite's needs) to a `Tensor`.
- Input image for `MobileFaceNet`: needs resizing to 112x112, RGB formatting, and values normalized to [-1, 1].
- Thresholds and timings are mapped 1:1 using `TimeInterval` and native Swift numbers.
