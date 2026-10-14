import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageNormalizer {
    // A bounded decode prevents one clipboard image from exhausting the app's memory.
    static let maximumPixels = 24_000_000

    static func normalize(_ data: Data) -> ImageContent? {
        autoreleasepool {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0,
                  width <= maximumPixels / height,
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

            let bytesPerRow = width * 4
            guard let context = CGContext(data: nil,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow,
                                          space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                  let pixelBuffer = context.data else { return nil }

            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let rendered = context.makeImage() else { return nil }

            var hasher = SHA256()
            hasher.update(data: Data("\(width)x\(height):".utf8))
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: pixelBuffer, count: bytesPerRow * height))
            let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()

            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, rendered, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return ImageContent(pngData: output as Data, pixelHash: hash, pixelWidth: width, pixelHeight: height)
        }
    }
}
