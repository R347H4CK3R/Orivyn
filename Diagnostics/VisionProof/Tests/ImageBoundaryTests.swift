import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import VisionProof

@MainActor
final class ImageBoundaryTests: XCTestCase {
    func fixture(width: Int = 64, height: Int = 32, orientation: Int = 1, transparent: Bool = false) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Pin fixture components to sRGB rather than the platform default color space.
        context.setFillColor(try XCTUnwrap(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: [1, 0, 0, transparent ? 0 : 1])))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let dst = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dst, try XCTUnwrap(context.makeImage()), [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dst))
        return data as Data
    }
    func testInvalidAndEncodedByteBound() {
        XCTAssertThrowsError(try ImageBoundary.decode(Data()))
        XCTAssertThrowsError(try ImageBoundary.decode(Data("not an image".utf8)))
        XCTAssertThrowsError(try ImageBoundary.decode(Data(repeating: 0, count: 10 * 1024 * 1024 + 1)))
    }
    func testPixelLimitsBeforeDecode() {
        XCTAssertThrowsError(try ImageBoundary.validateDimensions(width: 16385, height: 1))
        XCTAssertThrowsError(try ImageBoundary.validateDimensions(width: 10000, height: 4001))
        XCTAssertThrowsError(try ImageBoundary.validateDimensions(width: 0, height: 1))
        XCTAssertNoThrow(try ImageBoundary.validateDimensions(width: 10000, height: 4000))
    }
    func testOrientationsOneThroughEightAndPackedRGB() throws {
        for orientation in 1...8 {
            let rgb = try ImageBoundary.decode(fixture(orientation: orientation))
            XCTAssertEqual(rgb.width, orientation >= 5 ? 32 : 64)
            XCTAssertEqual(rgb.height, orientation >= 5 ? 64 : 32)
            XCTAssertEqual(rgb.bytes.count, rgb.width * rgb.height * 3)
            XCTAssertGreaterThan(rgb.bytes[0], 240)
            XCTAssertLessThan(rgb.bytes[1], 10)
            XCTAssertLessThan(rgb.bytes[2], 10)
        }
    }
    func testThumbnailAndWhiteAlphaComposite() throws {
        let large = try ImageBoundary.decode(fixture(width: 1024, height: 600))
        XCTAssertEqual(max(large.width, large.height), 512)
        XCTAssertLessThanOrEqual(large.bytes.count, 786432)
        let clear = try ImageBoundary.decode(fixture(transparent: true))
        XCTAssertTrue(clear.bytes.allSatisfy { $0 >= 250 })
    }
    func testTruncatedImageRefused() throws {
        let encoded = try fixture()
        XCTAssertThrowsError(try ImageBoundary.decode(encoded.prefix(encoded.count / 2)))
    }
    func testAllEightOrientationsTransformAsymmetricPixels() throws {
        var outputs = Set<Data>()
        for orientation in 1...8 {
            let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8,
                bytesPerRow: 256, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 16, height: 8))
            context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); context.fill(CGRect(x: 32, y: 16, width: 32, height: 16))
            let data = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), [kCGImagePropertyOrientation: orientation] as CFDictionary)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            let image = try ImageBoundary.decode(data as Data)
            XCTAssertEqual(image.width, orientation >= 5 ? 32 : 64)
            outputs.insert(image.bytes)
        }
        XCTAssertEqual(outputs.count, 8, "Mirrored and rotated variants must not silently ignore metadata")
    }
    func testMultipleFramesRefused() throws {
        let src = try XCTUnwrap(CGImageSourceCreateWithData(fixture() as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        let data = NSMutableData()
        let dst = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 2, nil))
        CGImageDestinationAddImage(dst, image, nil); CGImageDestinationAddImage(dst, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dst))
        XCTAssertThrowsError(try ImageBoundary.decode(data as Data))
    }
}
