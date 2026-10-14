import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageAssetInfo: Sendable, Equatable {
    let pixelWidth: Int
    let pixelHeight: Int
    let byteCount: Int64
}

@MainActor
final class ThumbnailImageCache {
    static let shared = ThumbnailImageCache()
    private let cache = NSCache<NSString, NSImage>()
    private var memorySource: (any DispatchSourceMemoryPressure)?

    init() {
        cache.countLimit = 16
        cache.totalCostLimit = 4 * 1024 * 1024 // 4MB limit
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            self?.clear()
        }
        source.resume()
        memorySource = source
    }

    deinit {
        memorySource?.cancel()
    }

    func image(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: NSImage, forKey key: String, cost: Int) {
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func clear() {
        cache.removeAllObjects()
    }
}

actor ImageThumbnailStore {
    private let root: URL
    private let cache = NSCache<NSString, NSData>()
    private var memorySource: (any DispatchSourceMemoryPressure)?

    init(root: URL) {
        self.root = root
        cache.countLimit = 12
        cache.totalCostLimit = 3 * 1024 * 1024 // 3MB limit
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            Task { [weak self] in
                await self?.clearCache()
            }
        }
        source.resume()
        self.memorySource = source
    }

    deinit {
        memorySource?.cancel()
    }

    func thumbnail(relativePath: String, maxPixelSize: Int) -> Data? {
        guard maxPixelSize > 0,
              let url = validatedURL(relativePath) else { return nil }
        let key = "\(relativePath)#\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: key) { return cached as Data }

        return autoreleasepool {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            let result = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return nil }
            let data = result as Data
            if maxPixelSize <= 300 {
                cache.setObject(result, forKey: key, cost: data.count)
            }
            return data
        }
    }

    func clearCache() {
        cache.removeAllObjects()
    }

    func metadata(relativePath: String) -> ImageAssetInfo? {
        guard let url = validatedURL(relativePath),
              let source = CGImageSourceCreateWithURL(url as CFURL,
                                                      [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return ImageAssetInfo(pixelWidth: width, pixelHeight: height, byteCount: Int64(bytes))
    }

    func originalData(relativePath: String) -> Data? {
        guard let url = validatedURL(relativePath) else { return nil }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private func validatedURL(_ relativePath: String) -> URL? {
        let parts = relativePath.split(separator: "/")
        guard parts.count == 3, parts[0] == "Assets", parts[1] == "Images",
              parts[2].hasSuffix(".png"), parts[2].dropLast(4).count == 64,
              parts[2].dropLast(4).allSatisfy({ $0.isHexDigit }) else { return nil }
        return root.appendingPathComponent(relativePath)
    }
}
