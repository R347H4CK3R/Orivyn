import XCTest
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import JarvisEVO

/// Exercises the production ImageIO → sRGB → packed-RGB → no-detail boundary.
/// Authored/syntax-parsed on Linux; execution requires the Apple test host.
@MainActor
final class ProductionVisionBoundaryTests: XCTestCase {
    private let block = 16
    private let palette: [[UInt8]] = [
        [255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255], [255, 255, 0, 255],
        [0, 255, 255, 255], [255, 0, 255, 255], [0, 0, 0, 255], [128, 128, 128, 255]
    ]

    private func image(width: Int, height: Int, rgba: [UInt8]) throws -> CGImage {
        XCTAssertEqual(rgba.count, width * height * 4)
        let provider = try XCTUnwrap(CGDataProvider(data: Data(rgba) as CFData))
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        // Explicit straight RGBA input allows meaningful hidden-color/alpha tests.
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func encoded(_ images: [CGImage], orientation: Int = 1) throws -> Data {
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.tiff.identifier as CFString, images.count, nil))
        for image in images {
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return bytes as Data
    }

    private func asymmetricImage() throws -> CGImage {
        var rgba = [UInt8]()
        for y in 0..<(2 * block) {
            for x in 0..<(4 * block) { rgba.append(contentsOf: palette[(y / block) * 4 + x / block]) }
        }
        return try image(width: 4 * block, height: 2 * block, rgba: rgba)
    }

    private func assertNoDetail(_ encoded: Data, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try ImageBoundary.decode(encoded), file: file, line: line) { error in
            guard let failure = error as? VisionPixelBoundary.Failure else {
                XCTFail("Expected decoded-pixel abstention, got \(error)", file: file, line: line)
                return
            }
            if case .noVisualDetail = failure { return }
            XCTFail("Expected noVisualDetail, got \(failure)", file: file, line: line)
        }
    }

    func testExactAllEightEXIFOrientationsAndRGBChannelOrder() throws {
        // Independent EXIF reference grids, in output row-major/top-to-bottom order.
        // Input is [A B C D; E F G H], not a symmetric solid-color fixture.
        let expected: [(columns: Int, rows: Int, cells: [Int])] = [
            (4, 2, [0, 1, 2, 3, 4, 5, 6, 7]), // 1: identity
            (4, 2, [3, 2, 1, 0, 7, 6, 5, 4]), // 2: horizontal mirror
            (4, 2, [7, 6, 5, 4, 3, 2, 1, 0]), // 3: 180 degrees
            (4, 2, [4, 5, 6, 7, 0, 1, 2, 3]), // 4: vertical mirror
            (2, 4, [0, 4, 1, 5, 2, 6, 3, 7]), // 5: transpose
            (2, 4, [4, 0, 5, 1, 6, 2, 7, 3]), // 6: 90 degrees clockwise
            (2, 4, [7, 3, 6, 2, 5, 1, 4, 0]), // 7: transverse
            (2, 4, [3, 7, 2, 6, 1, 5, 0, 4])  // 8: 90 degrees counterclockwise
        ]
        let input = try asymmetricImage()
        for (index, grid) in expected.enumerated() {
            let output = try ImageBoundary.decode(encoded([input], orientation: index + 1))
            XCTAssertEqual(output.width, grid.columns * block, "Orientation \(index + 1)")
            XCTAssertEqual(output.height, grid.rows * block, "Orientation \(index + 1)")
            XCTAssertEqual(output.bytes.count, output.width * output.height * 3)
            guard output.width == grid.columns * block, output.height == grid.rows * block,
                  output.bytes.count == output.width * output.height * 3 else { continue }
            // Inspect every pixel, including block edges; fail once per orientation
            // to keep a channel-order or reflection failure readable in CI.
            var mismatch: String?
            for y in 0..<output.height {
                for x in 0..<output.width {
                    let reference = palette[grid.cells[(y / block) * grid.columns + x / block]]
                    let offset = (y * output.width + x) * 3
                    for channel in 0..<3 where abs(Int(output.bytes[offset + channel]) - Int(reference[channel])) > 1 {
                        mismatch = "Orientation \(index + 1), pixel (\(x),\(y)), RGB channel \(channel): got \(output.bytes[offset + channel]), expected \(reference[channel])"
                        break
                    }
                    if mismatch != nil { break }
                }
                if mismatch != nil { break }
            }
            if let mismatch { XCTFail(mismatch) }
        }
    }

    func testThumbnailNeverExceeds512AndPreservesOrientationAspectRatio() throws {
        let width = 1024, height = 640
        var rgba = [UInt8](); rgba.reserveCapacity(width * height * 4)
        for _ in 0..<height {
            for x in 0..<width { rgba.append(contentsOf: x < width / 2 ? palette[0] : palette[2]) }
        }
        let large = try image(width: width, height: height, rgba: rgba)
        for (orientation, expectedWidth, expectedHeight) in [(1, 512, 320), (6, 320, 512)] {
            let output = try ImageBoundary.decode(encoded([large], orientation: orientation))
            XCTAssertEqual(output.width, expectedWidth)
            XCTAssertEqual(output.height, expectedHeight)
            XCTAssertLessThanOrEqual(max(output.width, output.height), 512)
            XCTAssertEqual(output.bytes.count, output.width * output.height * 3)
            XCTAssertLessThanOrEqual(output.bytes.count, 786_432)
        }
    }

    func testWhiteCompositingProducesPackedRGBForMixedTransparentAndOpaquePixels() throws {
        let input = try image(width: 3, height: 1, rgba: [255, 0, 0, 0, 0, 0, 255, 255, 255, 0, 0, 128])
        let output = try ImageBoundary.decode(encoded([input]))
        XCTAssertEqual(output.width, 3); XCTAssertEqual(output.height, 1)
        let expected: [UInt8] = [255, 255, 255, 0, 0, 255, 255, 127, 127]
        XCTAssertEqual(output.bytes.count, expected.count)
        guard output.bytes.count == expected.count else { return }
        for index in expected.indices {
            XCTAssertLessThanOrEqual(abs(Int(output.bytes[index]) - Int(expected[index])), 1, "RGB byte \(index)")
        }
    }

    func testUniformAndAlphaOnlyImagesAbstainAfterDecode() throws {
        let uniform = try image(width: 2, height: 2, rgba: Array(repeating: palette[0], count: 4).flatMap { $0 })
        assertNoDetail(try encoded([uniform]))
        // Hidden RGB varies, but zero alpha composites every pixel to white.
        let hidden = try image(width: 2, height: 2, rgba: [255,0,0,0, 0,255,0,0, 0,0,255,0, 0,0,0,0])
        assertNoDetail(try encoded([hidden]))
        // White with varying alpha also has no visible detail on the white canvas.
        let alphaOnly = try image(width: 2, height: 2, rgba: [255,255,255,0, 255,255,255,64, 255,255,255,128, 255,255,255,255])
        assertNoDetail(try encoded([alphaOnly]))
    }

    func testMalformedTruncatedAndOversizeEncodedDataAreRejected() throws {
        XCTAssertThrowsError(try ImageBoundary.decode(Data()))
        XCTAssertThrowsError(try ImageBoundary.decode(Data("not an image".utf8)))
        XCTAssertThrowsError(try ImageBoundary.decode(Data(repeating: 0, count: 10 * 1024 * 1024 + 1)))
        let valid = try encoded([asymmetricImage()])
        XCTAssertThrowsError(try ImageBoundary.decode(Data(valid.prefix(32))))
    }

    func testMultipleFramesAreRejectedInsteadOfSelectingFirstFrame() throws {
        let frame = try asymmetricImage()
        let data = try encoded([frame, frame])
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 2, "Fixture must really contain multiple frames")
        XCTAssertThrowsError(try ImageBoundary.decode(data))
    }
}
