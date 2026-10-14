import AppKit
import AVFoundation
import Foundation

enum VideoMetadataExtractor {
    static func extract(from url: URL) async -> (duration: Double?, thumbnail: ImageContent?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (nil, nil) }
        let asset = AVURLAsset(url: url)
        var durationSeconds: Double? = nil

        if let duration = try? await asset.load(.duration) {
            let seconds = duration.seconds
            if seconds > 0 && !seconds.isNaN && !seconds.isInfinite {
                durationSeconds = seconds
            }
        } else {
            let seconds = asset.duration.seconds
            if seconds > 0 && !seconds.isNaN && !seconds.isInfinite {
                durationSeconds = seconds
            }
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 800, height: 800)

        let targetTime = CMTime(seconds: min(1.0, (durationSeconds ?? 2.0) / 2.0), preferredTimescale: 600)
        var cgImageResult: CGImage? = nil

        if #available(macOS 13.0, *) {
            if let (cgImage, _) = try? await generator.image(at: targetTime) {
                cgImageResult = cgImage
            }
        }
        if cgImageResult == nil {
            cgImageResult = try? generator.copyCGImage(at: targetTime, actualTime: nil)
        }

        guard let cgImage = cgImageResult else {
            return (durationSeconds, nil)
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            return (durationSeconds, nil)
        }

        let normalized = ImageNormalizer.normalize(pngData)
        return (durationSeconds, normalized)
    }
}
