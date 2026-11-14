import Foundation
import ImageIO
import CoreGraphics

struct OwnedRGB: Sendable {
    let width: Int
    let height: Int
    let bytes: Data
}

enum ImageBoundary {
    enum Failure: Error { case bytes, format, dimensions, decode }
    static func validateDimensions(width: Int, height: Int) throws {
        guard width > 0, height > 0, width <= 16384, height <= 16384,
              width <= 40_000_000 / height else { throw Failure.dimensions }
    }
    // Caller supplies owned bytes, never an external URL/handle. No path/network API.
    static func decode(_ encoded: Data) throws -> OwnedRGB {
        guard !encoded.isEmpty, encoded.count <= 10 * 1024 * 1024 else { throw Failure.bytes }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(encoded as CFData, options),
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { throw Failure.format }
        try validateDimensions(width: width.intValue, height: height.intValue)
        let thumbOptions: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceShouldCache: false, kCGImageSourceShouldCacheImmediately: false]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary),
              image.width > 0, image.height > 0, image.width <= 512, image.height <= 512,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw Failure.decode }
        let w = image.width, h = image.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let rendered = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: w, height: h))
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard rendered else { throw Failure.decode }
        var rgb = Data(count: w * h * 3)
        rgb.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) in
            for pixel in 0..<(w * h) {
                for channel in 0..<3 { out[pixel * 3 + channel] = rgba[pixel * 4 + channel] }
            }
        }
        try VisionPixelBoundary.validate(width: w, height: h, rgb: rgb)
        return OwnedRGB(width: w, height: h, bytes: rgb)
    }
}
