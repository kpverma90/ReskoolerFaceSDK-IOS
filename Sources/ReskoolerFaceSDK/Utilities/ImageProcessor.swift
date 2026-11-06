import Foundation
import CoreGraphics
import CoreVideo
import Accelerate
import VideoToolbox

public class ImageProcessor {

    public static func cropAndResize(pixelBuffer: CVPixelBuffer, faceRect: CGRect, targetSize: Int) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let fw = faceRect.width
        let fh = faceRect.height

        let cx = faceRect.origin.x + fw / 2.0
        let cy = faceRect.origin.y + fh / 2.0

        let cropW = fw * (1.0 + 0.40)
        let cropH = fh * (1.0 + 0.50)
        let size = max(cropW, cropH)

        var cropRect = CGRect(
            x: cx - size / 2.0,
            y: cy - size / 2.0,
            width: size,
            height: size
        )

        cropRect.origin.x = max(0, cropRect.origin.x)
        cropRect.origin.y = max(0, cropRect.origin.y)
        if cropRect.maxX > CGFloat(width) { cropRect.size.width = CGFloat(width) - cropRect.origin.x }
        if cropRect.maxY > CGFloat(height) { cropRect.size.height = CGFloat(height) - cropRect.origin.y }

        guard let image = createCGImage(from: pixelBuffer) else { return nil }
        guard let cropped = image.cropping(to: cropRect) else { return nil }

        return resizeCGImage(cropped, to: CGSize(width: targetSize, height: targetSize))
    }

    private static func createCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        return cgImage
    }

    private static func resizeCGImage(_ image: CGImage, to size: CGSize) -> CVPixelBuffer? {
        let width = Int(size.width)
        let height = Int(size.height)

        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer)

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
