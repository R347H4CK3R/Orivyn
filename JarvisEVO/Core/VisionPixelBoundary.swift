import Foundation

/// Refuses images with no discernible variation, based only on owned RGB pixels.
/// No OCR, expected labels, filename, model answer or external service is used.
enum VisionPixelBoundary {
    enum Failure: Error, LocalizedError {
        case invalid, noVisualDetail
        var errorDescription: String? {
            switch self {
            case .invalid: "The image could not be prepared safely."
            case .noVisualDetail: "This image has no discernible visual detail. Choose a clearer image."
            }
        }
    }
    static func validate(width: Int, height: Int, rgb: Data) throws {
        guard width > 0, height > 0, width <= 512, height <= 512,
              rgb.count == width * height * 3 else { throw Failure.invalid }
        var low = [UInt8](repeating: 255, count: 3)
        var high = [UInt8](repeating: 0, count: 3)
        for (index, value) in rgb.enumerated() {
            let channel = index % 3
            low[channel] = min(low[channel], value); high[channel] = max(high[channel], value)
            if (0..<3).contains(where: { Int(high[$0]) - Int(low[$0]) > 2 }) { return }
        }
        // A flat color or <=2/255 codec noise is not evidence of an object.
        throw Failure.noVisualDetail
    }
}
