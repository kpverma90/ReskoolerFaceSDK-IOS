# Android Architecture Reference

## Overview
The Android SDK relies on CameraX, ML Kit, and TensorFlow Lite to detect faces, evaluate their quality, determine if they are live, and match them against known staff members.

## Key Components

### Camera (CameraManager)
- Uses `androidx.camera.core` for CameraX operations.
- `CameraSelector.LENS_FACING_FRONT` is used by default.
- Pushes ImageProxy frames to an `ImageAnalysis.Analyzer`.
- Emits exceptions for start or runtime issues.

### Face Detection (FaceDetectorEngine)
- Uses `com.google.mlkit.vision.face`.
- Options: `PERFORMANCE_MODE_FAST`, `LANDMARK_MODE_ALL`, `CLASSIFICATION_MODE_ALL`.
- Min face size: 0.15.
- Tracking enabled.
- Takes `InputImage` and returns a list of ML Kit `Face` objects.

### Quality Gate (FaceQualityGate)
- Runs before heavy ML logic to avoid processing unviable faces.
- Checks: min face width (14% of frame), min area (1.8% of frame), if the face is inside bounds, and pose limits (Yaw: 40, Pitch: 30, Roll: 35).
- Rejects non-compliant faces with issues like `TOO_SMALL`, `PARTIAL_FACE`, `EXTREME_POSE`.

### Liveness Detection (AntiSpoofEngine)
- Uses `model_2_7.tflite` and `model_4_0.tflite`.
- Checks if a face is live, evaluating scores against a history sequence.
- Model tensors use 256x256 float32 inputs for one model, outputting logits for C0, C1, C2.

### Face Recognition (FaceEmbeddingEngine & FaceRecognizer)
- Uses `MobileFaceNet.tflite`.
- Input size 112x112x3 (float32, batch size 2).
- Returns embedding vector (size 192).
- Image crop margins: X=20%, Y=25%.
- Normalizes pixel values via `(value / 127.5f) - 1.0f`.
- The matching uses cosine similarity against embeddings in `EmbeddingGallery`.
- Default threshold: 0.70.

### Kiosk & Attendance Sessions
- Configuration:
  - Verify threshold: 0.70.
  - Watchdog interval: 2000ms.
  - Kiosk result hold: 2500ms.
