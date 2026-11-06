# ReskoolerFaceSDK-IOS

Native iOS Swift SDK for Reskooler Face Attendance.

## Expo / EAS Build Integration

This project is structured as an Expo module.

1. Install it into your app via a local path: `npm install file:../ReskoolerFaceSDK-IOS`
2. Add necessary permissions in `app.json`:
   ```json
   "ios": {
     "infoPlist": {
       "NSCameraUsageDescription": "This app uses the camera for Face Attendance."
     }
   }
   ```
3. Your main app code can invoke it via:
   ```javascript
   import { startFaceSDK, setGallery, addFaceResultListener } from 'reskooler-face-sdk';

   addFaceResultListener((event) => {
     console.log("Face result:", event);
   });

   startFaceSDK("kiosk");
   ```
4. Run `eas build --platform ios` to initiate remote compilation on macOS.
