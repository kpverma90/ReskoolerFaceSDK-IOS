Pod::Spec.new do |s|
  s.name             = 'ReskoolerFaceSDK'
  s.version          = '1.0.0'
  s.summary          = 'Native iOS Swift SDK for Reskooler Face Attendance.'
  s.description      = <<-DESC
    ReskoolerFaceSDK provides face detection, recognition, and liveness detection.
    It internally bundles TensorFlow Lite and Google ML Kit.
                       DESC
  s.homepage         = 'https://github.com/kpverma90/ReskoolerFaceSDK-IOS'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Your Name' => 'yourname@email.com' }
  s.source           = { :git => 'https://github.com/kpverma90/ReskoolerFaceSDK-IOS.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.0'

  s.source_files = 'Sources/ReskoolerFaceSDK/**/*'

  # Bundle the models in a resource bundle to avoid namespace collisions and ensure they can be located
  s.resource_bundles = {
    'ReskoolerFaceSDK_Models' => ['Sources/ReskoolerFaceSDK/Models/*.tflite']
  }

  # Define internal SDK dependencies
  s.dependency 'TensorFlowLiteSwift'
  s.dependency 'GoogleMLKit/FaceDetection'

  s.static_framework = true
end
