import AppKit
import Foundation

enum ClipboardWriteContent {
    case text(String)
    case url(String)
    case image(Data)
    case files([URL])
    case richText(plain: String, rtfData: Data)
}

@MainActor
protocol ContentPasteboard: AnyObject {
    var changeCount: Int { get }
    func readSnapshot() -> ClipboardSnapshot?
    func write(_ content: ClipboardWriteContent) -> Bool
}

@MainActor
final class SystemContentPasteboard: ContentPasteboard {
    private let pasteboard: NSPasteboard
    private let pngType = NSPasteboard.PasteboardType("public.png")
    private let urlType = NSPasteboard.PasteboardType("public.url")

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    func readSnapshot() -> ClipboardSnapshot? {
        autoreleasepool {
            let fileObjects = pasteboard.readObjects(forClasses: [NSURL.self],
                                                      options: [.urlReadingFileURLsOnly: true]) ?? []
            let files = fileObjects.compactMap { ($0 as? NSURL).map { $0 as URL } }.filter(\.isFileURL)
            // Read exactly one image representation per change. Prefer PNG, then TIFF,
            // then an NSImage conversion for apps that expose neither data type.
            let imageData = pasteboard.data(forType: pngType)
                ?? pasteboard.data(forType: .tiff)
                ?? (pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage)?.tiffRepresentation
            let url = pasteboard.string(forType: urlType)
            let text = pasteboard.string(forType: .string)
            let rtfData = pasteboard.data(forType: .rtf)
            guard !files.isEmpty || imageData != nil || url != nil || text != nil || rtfData != nil else { return nil }
            return ClipboardSnapshot(fileURLs: files, imageData: imageData, urlString: url, plainText: text, rtfData: rtfData)
        }
    }

    func write(_ content: ClipboardWriteContent) -> Bool {
        pasteboard.clearContents()
        switch content {
        case .text(let text):
            return pasteboard.setString(text, forType: .string)
        case .url(let url):
            let typed = pasteboard.setString(url, forType: urlType)
            let plain = pasteboard.setString(url, forType: .string)
            return typed && plain
        case .image(let pngData):
            return autoreleasepool {
                let png = pasteboard.setData(pngData, forType: pngType)
                if let tiff = NSImage(data: pngData)?.tiffRepresentation {
                    _ = pasteboard.setData(tiff, forType: .tiff)
                }
                return png
            }
        case .files(let urls):
            return !urls.isEmpty && pasteboard.writeObjects(urls.map { $0 as NSURL })
        case .richText(let plain, let rtfData):
            let rtf = pasteboard.setData(rtfData, forType: .rtf)
            let text = pasteboard.setString(plain, forType: .string)
            return rtf || text
        }
    }
}

@MainActor
final class ClipboardService {
    nonisolated static let pollingInterval: TimeInterval = 0.20

    private let pasteboard: any ContentPasteboard
    private var interval: TimeInterval
    private var lastChangeCount: Int
    private var timer: Timer?
    private(set) var isCapturing = false
    // Counts unobserved changeCount increments, not recoverable clipboard items.
    private(set) var missedChangeCountDelta = 0
    var onCapture: ((ClipboardInput) -> Void)?

    init(pasteboard: any ContentPasteboard, interval: TimeInterval = ClipboardService.pollingInterval) {
        self.pasteboard = pasteboard
        self.interval = interval
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard !isCapturing else { return }
        lastChangeCount = pasteboard.changeCount
        isCapturing = true
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isCapturing = false
        lastChangeCount = pasteboard.changeCount
    }

    func setPollingInterval(_ value: TimeInterval) {
        guard [0.2, 0.3, 0.5, 1.0].contains(value), interval != value else { return }
        let resume = isCapturing
        if resume { stop() }
        interval = value
        if resume { start() }
    }

    func copyToPasteboard(_ content: ClipboardWriteContent) -> Bool {
        let success = pasteboard.write(content)
        lastChangeCount = pasteboard.changeCount
        return success
    }

    func poll() {
        autoreleasepool {
            guard isCapturing else { return }
            let observedCount = pasteboard.changeCount
            guard observedCount != lastChangeCount else { return }
            if observedCount > lastChangeCount {
                missedChangeCountDelta += max(0, observedCount - lastChangeCount - 1)
            }
            lastChangeCount = observedCount
            guard let snapshot = pasteboard.readSnapshot(),
                  pasteboard.changeCount == observedCount,
                  let content = ClipboardClassifier.classify(snapshot) else { return }
            onCapture?(content)
        }
    }
}
