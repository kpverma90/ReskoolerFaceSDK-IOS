# ReskoolerFaceSDK-IOS

Native iOS Swift SDK for Reskooler Face Attendance.

## Integration into iOS Application

This project is a pure Native Swift library. Because Google distributes ML Kit specifically via CocoaPods as static frameworks, the recommended way to integrate this SDK while maintaining encapsulated dependencies is through CocoaPods.

### 1. CocoaPods Installation (Recommended)

To allow the SDK to automatically manage `GoogleMLKit/FaceDetection` and `TensorFlowLiteSwift`, use CocoaPods. In your host application's `Podfile`, point to this repository:

```ruby
pod 'ReskoolerFaceSDK', :git => 'https://github.com/kpverma90/ReskoolerFaceSDK-IOS.git'
```

Run `pod install`. This automatically resolves all dependencies internal to the SDK.

### 2. Swift Package Manager (SPM)

Google ML Kit does **not** officially support Swift Package Manager. If you integrate this repository via SPM, `Package.swift` cannot automatically download ML Kit. You would have to either:
1. Wrap ML Kit manually into an `.xcframework` and host it yourself.
2. Link ML Kit separately via CocoaPods in your host application and use SPM only for the Swift source files.

Because of this limitation, the provided `Package.swift` omits ML Kit. CocoaPods is the officially supported distribution method.

### Setup and Usage

1. In your `Info.plist`, ensure you request camera permissions:
   ```xml
   <key>NSCameraUsageDescription</key>
   <string>This app uses the camera for Face Attendance.</string>
   ```
2. Import the SDK in your Swift application:
   ```swift
   import ReskoolerFaceSDK

   let faceSDK = FaceSDK()

   faceSDK.onResult = { result in
       print("Face Result:", result)
   }

   faceSDK.start(mode: .kiosk)
   ```
3. Stop the SDK when it is no longer required:
   ```swift
   faceSDK.stop()
   ```

**Note**: To bridge this to React Native or Expo, you should write a native module adapter in your host application code that interacts with the `FaceSDK` class.
