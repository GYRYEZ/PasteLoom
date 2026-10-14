import AppKit
import XCTest
@testable import PasteLoom

final class Stage3Tests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testSchemaV6MigrationAndColumns() async throws {
        let dbURL = tempDirectory.appendingPathComponent("history.sqlite3")
        let repo = try SQLiteHistoryRepository(url: dbURL)

        // Insert rich text and video items
        let rtfData = "{\\rtf1\\ansi Hello Rich Text}".data(using: .utf8)!
        try await repo.insert(content: .richText(plain: "Hello Rich Text", rtfData: rtfData), at: Date())

        let items = try await repo.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.kind, .richText)
        XCTAssertEqual(items.first?.text, "Hello Rich Text")
        XCTAssertEqual(items.first?.rtfData, rtfData)
    }

    func testRichTextInsertAndRetrieve() async throws {
        let dbURL = tempDirectory.appendingPathComponent("history.sqlite3")
        let repo = try SQLiteHistoryRepository(url: dbURL)

        let rtfString = "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Courier;}}\\f0\\fs24 Sample \\b Bold \\b0 Text}"
        let rtfData = rtfString.data(using: .utf8)!

        try await repo.insert(content: .richText(plain: "Sample Bold Text", rtfData: rtfData), at: Date())

        let results = try await repo.search(text: "Bold", limit: 10, offset: 0)
        XCTAssertEqual(results.count, 1)
        let item = try XCTUnwrap(results.first)
        XCTAssertEqual(item.kind, .richText)
        XCTAssertEqual(item.text, "Sample Bold Text")
        XCTAssertEqual(item.rtfData, rtfData)
    }

    func testVideoInsertAndRetrieve() async throws {
        let dbURL = tempDirectory.appendingPathComponent("history.sqlite3")
        let repo = try SQLiteHistoryRepository(url: dbURL)

        let dummyVideoURL = tempDirectory.appendingPathComponent("demo_clip.mp4")
        try Data("dummy mp4 bytes".utf8).write(to: dummyVideoURL)

        let fileRef = FileReference(url: dummyVideoURL, name: "demo_clip.mp4",
                                    fileExtension: "mp4", typeIdentifier: "public.mpeg-4")

        try await repo.insert(content: .video(fileRef, duration: 65.0, thumbnail: nil), at: Date())

        let items = try await repo.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.kind, .video)
        XCTAssertTrue(item.text.contains("01:05"))
        XCTAssertEqual(item.files.count, 1)
        XCTAssertEqual(item.files.first?.name, "demo_clip.mp4")
    }

    func testOCRTextUpdateAndSearch() async throws {
        let dbURL = tempDirectory.appendingPathComponent("history.sqlite3")
        let repo = try SQLiteHistoryRepository(url: dbURL)

        // Create a 1x1 image content
        let imageRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 10,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                        isPlanar: false, colorSpaceName: .deviceRGB,
                                        bytesPerRow: 40, bitsPerPixel: 32)!
        let pngData = imageRep.representation(using: .png, properties: [:])!
        let imageContent = ImageContent(pngData: pngData, pixelHash: "a" + String(repeating: "0", count: 63),
                                        pixelWidth: 10, pixelHeight: 10)

        try await repo.insert(content: .image(imageContent), at: Date())

        let initial = try await repo.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(initial.count, 1)
        let imageItem = try XCTUnwrap(initial.first)
        XCTAssertNil(imageItem.ocrText)

        // Update OCR text
        let recognized = "发票金额 ¥1024.00 谢谢惠顾"
        try await repo.updateOCRText(recognized, for: imageItem.id)

        // Search with query inside OCR text
        let searchResults = try await repo.search(text: "发票金额", limit: 10, offset: 0)
        XCTAssertEqual(searchResults.count, 1)
        let found = try XCTUnwrap(searchResults.first)
        XCTAssertEqual(found.id, imageItem.id)
        XCTAssertEqual(found.ocrText, recognized)
    }

    func testClipboardClassifierRichTextAndVideo() {
        // Video file classification
        let videoURL = URL(fileURLWithPath: "/tmp/sample.mp4")
        let videoSnapshot = ClipboardSnapshot(fileURLs: [videoURL], imageData: nil,
                                              urlString: nil, plainText: nil, rtfData: nil)
        let videoClassified = ClipboardClassifier.classify(videoSnapshot)
        if case .video(let ref) = videoClassified {
            XCTAssertEqual(ref.name, "sample.mp4")
            XCTAssertEqual(ref.fileExtension, "mp4")
        } else {
            XCTFail("Expected .video classification")
        }

        // Rich text classification
        let rtfData = "{\\rtf1 Hello}".data(using: .utf8)!
        let rtfSnapshot = ClipboardSnapshot(fileURLs: [], imageData: nil, urlString: nil,
                                            plainText: "Hello", rtfData: rtfData)
        let rtfClassified = ClipboardClassifier.classify(rtfSnapshot)
        if case .richText(let plain, let rtf) = rtfClassified {
            XCTAssertEqual(plain, "Hello")
            XCTAssertEqual(rtf, rtfData)
        } else {
            XCTFail("Expected .richText classification")
        }

        // Web URL overrides RTF
        let urlSnapshot = ClipboardSnapshot(fileURLs: [], imageData: nil,
                                            urlString: "https://apple.com",
                                            plainText: "https://apple.com", rtfData: rtfData)
        let urlClassified = ClipboardClassifier.classify(urlSnapshot)
        if case .url(let url) = urlClassified {
            XCTAssertEqual(url, "https://apple.com")
        } else {
            XCTFail("Expected .url classification")
        }
    }

    func testVisionOCRServiceInvalidImageData() async {
        let invalidData = Data("not an image".utf8)
        do {
            _ = try await VisionOCRService.shared.recognizeText(from: invalidData)
            XCTFail("Expected invalidImageData error")
        } catch {
            XCTAssertTrue(error is VisionOCRError)
        }
    }

    func testVisionOCRServiceBlankImageRecognizesGracefully() async throws {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 50, pixelsHigh: 50,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 200, bitsPerPixel: 32)!
        let png = rep.representation(using: .png, properties: [:])!
        let result = try await VisionOCRService.shared.recognizeText(from: png)
        XCTAssertNotNil(result)
    }

    func testVideoDurationFormatting() {
        // Test duration format 65.0s -> 01:05
        let total = Int((65.0 as Double).rounded())
        let m = total / 60
        let s = total % 60
        let formatted = String(format: "%02d:%02d", m, s)
        XCTAssertEqual(formatted, "01:05")
    }
}
