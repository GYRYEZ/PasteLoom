import AppKit
import XCTest
@testable import PasteLoom

@MainActor
final class ClipboardServiceTests: XCTestCase {
    func testCapturesOneEventAndSkipsOwnWrite() {
        let pasteboard = FakePasteboard()
        let service = ClipboardService(pasteboard: pasteboard)
        var captured: [ClipboardInput] = []
        service.onCapture = { captured.append($0) }
        service.start()
        pasteboard.externalCopy("one")
        service.poll()
        service.poll()
        XCTAssertEqual(captured.count, 1)

        XCTAssertTrue(service.copyToPasteboard(.text("one")))
        service.poll()
        XCTAssertEqual(captured.count, 1)

        pasteboard.externalCopy("one")
        service.poll()
        XCTAssertEqual(captured.count, 2)
        service.stop()
    }

    func testResumeDoesNotCaptureClipboardFromPause() {
        let pasteboard = FakePasteboard()
        let service = ClipboardService(pasteboard: pasteboard)
        var count = 0
        service.onCapture = { _ in count += 1 }
        service.start()
        service.stop()
        pasteboard.externalCopy("paused")
        service.start()
        service.poll()
        XCTAssertEqual(count, 0)
        pasteboard.externalCopy("new")
        service.poll()
        XCTAssertEqual(count, 1)
        service.stop()
    }

    func testIdlePollingOnlyReadsChangeCount() {
        let pasteboard = FakePasteboard()
        let service = ClipboardService(pasteboard: pasteboard)
        service.start()
        for _ in 0..<100 { service.poll() }
        XCTAssertEqual(pasteboard.snapshotReadCount, 0)
        XCTAssertEqual(service.missedChangeCountDelta, 0)
        XCTAssertEqual(ClipboardService.pollingInterval, 0.20)
        service.stop()
    }

    func testBurstReadsOnlyLatestWithoutInventingMissedItems() {
        let pasteboard = FakePasteboard()
        let service = ClipboardService(pasteboard: pasteboard)
        var captured: [ClipboardInput] = []
        service.onCapture = { captured.append($0) }
        service.start()

        pasteboard.externalCopy("first")
        pasteboard.externalCopy("second")
        pasteboard.externalCopy("third")
        service.poll()
        service.poll()

        XCTAssertEqual(captured.count, 1)
        guard case .text("third") = captured.first else { return XCTFail("Only the latest payload can be read") }
        XCTAssertEqual(service.missedChangeCountDelta, 2)
        XCTAssertEqual(pasteboard.snapshotReadCount, 1)
        service.stop()
    }

    func testPolledBurstRetainsTypeAndOneRecordPerEvent() {
        let pasteboard = FakePasteboard()
        let service = ClipboardService(pasteboard: pasteboard)
        var captured: [ClipboardInput] = []
        service.onCapture = { captured.append($0) }
        service.start()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("round25-one.txt")
        let second = FileManager.default.temporaryDirectory.appendingPathComponent("round25-two.txt")
        let events: [ClipboardSnapshot] = [
            ClipboardSnapshot(fileURLs: [], imageData: nil, urlString: nil, plainText: "plain"),
            ClipboardSnapshot(fileURLs: [], imageData: nil, urlString: "https://example.com/burst", plainText: "https://example.com/burst"),
            ClipboardSnapshot(fileURLs: [], imageData: TestImage.makePNG(), urlString: nil, plainText: nil),
            ClipboardSnapshot(fileURLs: [file], imageData: nil, urlString: nil, plainText: nil),
            ClipboardSnapshot(fileURLs: [file, second], imageData: nil, urlString: nil, plainText: nil)
        ]
        for event in events {
            pasteboard.externalCopy(event)
            service.poll()
            service.poll()
        }
        XCTAssertEqual(captured.count, 5)
        guard case .text("plain") = captured[0],
              case .url("https://example.com/burst") = captured[1],
              case .image = captured[2],
              case .files(let one) = captured[3],
              case .files(let multiple) = captured[4] else { return XCTFail("A content type regressed") }
        XCTAssertEqual(one.map(\.url), [file])
        XCTAssertEqual(multiple.map(\.url), [file, second])
        XCTAssertEqual(service.missedChangeCountDelta, 0)
        service.stop()
    }

    func testCopyBackOfEveryTypeDoesNotRecapture() {
        let pasteboard = FakePasteboard()
        let service = ClipboardService(pasteboard: pasteboard)
        var captured = 0
        service.onCapture = { _ in captured += 1 }
        service.start()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("round25-file.txt")
        let values: [ClipboardWriteContent] = [
            .text("plain"), .url("https://example.com/self"),
            .image(TestImage.makePNG()), .files([file])
        ]
        for value in values {
            XCTAssertTrue(service.copyToPasteboard(value))
            service.poll()
        }
        XCTAssertEqual(captured, 0)
        service.stop()
    }

    func testChangeDuringSnapshotReadRetriesOnlyNewerPayload() {
        let pasteboard = FakePasteboard()
        let service = ClipboardService(pasteboard: pasteboard)
        var captured: [ClipboardInput] = []
        service.onCapture = { captured.append($0) }
        service.start()
        pasteboard.externalCopy("old")
        pasteboard.onRead = { pasteboard.externalCopy("new") }
        service.poll()
        XCTAssertTrue(captured.isEmpty)
        pasteboard.onRead = nil
        service.poll()
        XCTAssertEqual(captured.count, 1)
        guard case .text("new") = captured[0] else { return XCTFail("Only the stable payload should be captured") }
        service.stop()
    }

    func testSystemPasteboardWritesTypedContent() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let adapter = SystemContentPasteboard(pasteboard: board)

        XCTAssertTrue(adapter.write(.text("plain")))
        XCTAssertEqual(board.string(forType: .string), "plain")

        XCTAssertTrue(adapter.write(.url("https://example.com/path")))
        XCTAssertEqual(board.string(forType: NSPasteboard.PasteboardType("public.url")), "https://example.com/path")
        XCTAssertEqual(board.string(forType: .string), "https://example.com/path")
        let copiedURL = (board.readObjects(forClasses: [NSURL.self], options: nil)?.first as? NSURL)?.absoluteString
        XCTAssertEqual(copiedURL, "https://example.com/path")

        let image = TestImage.makePNG()
        XCTAssertTrue(adapter.write(.image(image)))
        XCTAssertEqual(board.data(forType: NSPasteboard.PasteboardType("public.png")), image)
        XCTAssertNotNil(board.data(forType: .tiff))

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("round2-file.txt")
        let secondFile = FileManager.default.temporaryDirectory.appendingPathComponent("round2-second-file.txt")
        XCTAssertTrue(adapter.write(.files([file, secondFile])))
        XCTAssertTrue(board.types?.contains(.fileURL) == true)
        XCTAssertEqual(adapter.readSnapshot()?.fileURLs, [file, secondFile])
    }

    func testMultipleImageRepresentationsYieldOneLogicalSnapshot() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let png = TestImage.makePNG()
        let tiff = try XCTUnwrap(NSBitmapImageRep(data: png)?.tiffRepresentation)
        board.declareTypes([NSPasteboard.PasteboardType("public.png"), .tiff], owner: nil)
        XCTAssertTrue(board.setData(png, forType: NSPasteboard.PasteboardType("public.png")))
        XCTAssertTrue(board.setData(tiff, forType: .tiff))
        let adapter = SystemContentPasteboard(pasteboard: board)
        let snapshot = try XCTUnwrap(adapter.readSnapshot())
        guard case .image(let data) = ClipboardClassifier.classify(snapshot) else {
            return XCTFail("Expected one image input")
        }
        XCTAssertEqual(data, png)
        XCTAssertEqual(ImageNormalizer.normalize(data)?.pixelHash,
                       ImageNormalizer.normalize(tiff)?.pixelHash)
    }

    func testTwoImageChangeCountsAndFastDistinctImageDoNotLoseData() async throws {
        let board = FakePasteboard()
        let service = ClipboardService(pasteboard: board)
        var captured: [ClipboardInput] = []
        service.onCapture = { captured.append($0) }
        service.start()
        let first = TestImage.makePNG(color: .red)
        let second = TestImage.makePNG(color: .blue)
        for data in [first, first, second] {
            board.externalCopy(.init(fileURLs: [], imageData: data, urlString: nil, plainText: nil))
            service.poll()
        }
        service.stop()
        XCTAssertEqual(captured.count, 3)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try SQLiteHistoryRepository(url: directory.appendingPathComponent("history.sqlite3"))
        for (index, input) in captured.enumerated() {
            guard case .image(let data) = input, let image = ImageNormalizer.normalize(data) else {
                return XCTFail("Expected normalized image")
            }
            try await repository.insert(content: .image(image), at: Date(timeIntervalSince1970: 1 + Double(index) * 0.1))
        }
        let items = try await repository.search(text: "", limit: 10, offset: 0)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(Set(items.compactMap(\.contentHash)).count, 2)
    }
}

@MainActor
private final class FakePasteboard: ContentPasteboard {
    private var counter = 0
    private var snapshot = ClipboardSnapshot(fileURLs: [], imageData: nil, urlString: nil, plainText: nil)
    private(set) var snapshotReadCount = 0
    var onRead: (() -> Void)?

    var changeCount: Int { counter }

    func readSnapshot() -> ClipboardSnapshot? {
        snapshotReadCount += 1
        let result = snapshot
        onRead?()
        return result
    }

    func write(_ content: ClipboardWriteContent) -> Bool {
        switch content {
        case .text(let value): snapshot = ClipboardSnapshot(fileURLs: [], imageData: nil, urlString: nil, plainText: value)
        case .url(let value): snapshot = ClipboardSnapshot(fileURLs: [], imageData: nil, urlString: value, plainText: value)
        case .image(let data): snapshot = ClipboardSnapshot(fileURLs: [], imageData: data, urlString: nil, plainText: nil)
        case .files(let files): snapshot = ClipboardSnapshot(fileURLs: files, imageData: nil, urlString: nil, plainText: nil)
        case .richText(let plain, let rtfData): snapshot = ClipboardSnapshot(fileURLs: [], imageData: nil, urlString: nil, plainText: plain, rtfData: rtfData)
        }
        counter += 1
        return true
    }

    func externalCopy(_ value: String) {
        externalCopy(ClipboardSnapshot(fileURLs: [], imageData: nil, urlString: nil, plainText: value))
    }

    func externalCopy(_ value: ClipboardSnapshot) {
        snapshot = value
        counter += 1
    }
}
