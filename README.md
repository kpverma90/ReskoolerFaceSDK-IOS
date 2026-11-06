# ReskoolerFaceSDK-IOS

Native iOS Swift SDK for Reskooler Face Attendance.

## Integration into iOS Application

This project is a pure Native Swift package and can be integrated using the Swift Package Manager.

1. Add the package to your iOS project dependencies.
2. Because Google MLKit Face Detection does not officially support SPM, you must ensure your host application links `GoogleMLKit/FaceDetection` (e.g. via CocoaPods or XCFrameworks) so this module can compile.
3. In your `Info.plist`, ensure you request camera permissions:
   ```xml
   <key>NSCameraUsageDescription</key>
   <string>This app uses the camera for Face Attendance.</string>
   ```
4. Import the SDK in your Swift application:
   ```swift
   import ReskoolerFaceSDK

   let faceSDK = FaceSDK()

   faceSDK.onResult = { result in
       print("Face Result:", result)
   }

   faceSDK.start(mode: .kiosk)
   ```
5. Stop the SDK when it is no longer required:
   ```swift
   faceSDK.stop()
   ```

**Note**: To bridge this to React Native or Expo, you should write a native module adapter in your host application code that interacts with the `FaceSDK` class.
