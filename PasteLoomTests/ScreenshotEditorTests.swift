import AppKit
import XCTest
@testable import PasteLoom

@MainActor
final class ScreenshotEditorTests: XCTestCase {
    func testHistoryPreviewRoutesAllCurrentContentTypes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("first.txt")
        let secondURL = directory.appendingPathComponent("second.txt")
        try Data("file".utf8).write(to: firstURL)
        let first = FileReference(url: firstURL, name: "first.txt", fileExtension: "txt", typeIdentifier: nil)
        let second = FileReference(url: secondURL, name: "second.txt", fileExtension: "txt", typeIdentifier: nil)
        func item(_ kind: HistoryKind, files: [FileReference] = []) -> HistoryItem {
            HistoryItem(id: UUID(), kind: kind, text: "preview", capturedAt: Date(),
                        imageRelativePath: nil, contentHash: nil, files: files)
        }
        XCTAssertEqual(HistoryPreviewRoute.forItem(item(.text)), .detail)
        XCTAssertEqual(HistoryPreviewRoute.forItem(item(.url)), .detail)
        XCTAssertEqual(HistoryPreviewRoute.forItem(item(.image)), .detail)
        XCTAssertEqual(HistoryPreviewRoute.forItem(item(.file, files: [first])), .quickLook(firstURL))
        XCTAssertEqual(HistoryPreviewRoute.forItem(item(.file, files: [first, second])), .detail)
        XCTAssertEqual(HistoryPreviewRoute.forItem(item(.file, files: [second])), .detail)
    }

    func testAnnotationRenderAndCropPreserveExpectedPixelDimensions() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 120, height: 80,
                                              bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        let sourceImage = try XCTUnwrap(context.makeImage())
        let source = try XCTUnwrap(NSBitmapImageRep(cgImage: sourceImage)
            .representation(using: .png, properties: [:]))
        let mark = ScreenshotMark(tool: .rectangle,
                                  start: CGPoint(x: 0.3, y: 0.3),
                                  end: CGPoint(x: 0.7, y: 0.7),
                                  points: [], text: "", colorIndex: 0, lineWidth: 4)
        let output = try XCTUnwrap(ScreenshotAnnotationRenderer.renderPNG(
            source: source, marks: [mark], crop: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            colors: [.red]))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: output))
        XCTAssertEqual(bitmap.pixelsWide, 60)
        XCTAssertEqual(bitmap.pixelsHigh, 40)
        XCTAssertNotEqual(output, source)
    }

    func testImagePrintServiceConfiguresOrientationAndPagination() throws {
        // Landscape image
        let landscapeImage = NSImage(size: NSSize(width: 800, height: 400))
        let landscapeOp = ImagePrintService.shared.makePrintOperation(
            for: landscapeImage,
            jobTitle: "Test Landscape",
            showsPrintPanel: false,
            showsProgressPanel: false
        )
        XCTAssertEqual(landscapeOp.jobTitle, "Test Landscape")
        XCTAssertEqual(landscapeOp.printInfo.orientation, .landscape)
        XCTAssertEqual(landscapeOp.printInfo.horizontalPagination, .fit)
        XCTAssertEqual(landscapeOp.printInfo.verticalPagination, .fit)
        XCTAssertTrue(landscapeOp.printInfo.isHorizontallyCentered)
        XCTAssertTrue(landscapeOp.printInfo.isVerticallyCentered)
        XCTAssertTrue(landscapeOp.view is ImagePrintCanvasView)

        // Portrait image
        let portraitImage = NSImage(size: NSSize(width: 400, height: 800))
        let portraitOp = ImagePrintService.shared.makePrintOperation(
            for: portraitImage,
            jobTitle: "Test Portrait",
            showsPrintPanel: false,
            showsProgressPanel: false
        )
        XCTAssertEqual(portraitOp.jobTitle, "Test Portrait")
        XCTAssertEqual(portraitOp.printInfo.orientation, .portrait)
        XCTAssertEqual(portraitOp.printInfo.horizontalPagination, .fit)
        XCTAssertEqual(portraitOp.printInfo.verticalPagination, .fit)
        XCTAssertTrue(portraitOp.printInfo.isHorizontallyCentered)
        XCTAssertTrue(portraitOp.printInfo.isVerticallyCentered)
        XCTAssertTrue(portraitOp.view is ImagePrintCanvasView)
    }

    func testImagePrintCanvasViewKnowsSinglePageAndDraws() throws {
        let image = NSImage(size: NSSize(width: 200, height: 100))
        image.lockFocus()
        NSColor.systemRed.drawSwatch(in: NSRect(x: 0, y: 0, width: 200, height: 100))
        image.unlockFocus()

        let printView = ImagePrintCanvasView(image: image, frame: NSRect(x: 0, y: 0, width: 500, height: 700))
        var range = NSRange(location: 0, length: 0)
        let knows = printView.knowsPageRange(&range)
        XCTAssertTrue(knows)
        XCTAssertEqual(range.location, 1)
        XCTAssertEqual(range.length, 1)
        XCTAssertEqual(printView.rectForPage(1), printView.bounds)

        // Test drawing into a bitmap representation
        let rep = try XCTUnwrap(printView.bitmapImageRepForCachingDisplay(in: printView.bounds))
        printView.cacheDisplay(in: printView.bounds, to: rep)
        XCTAssertGreaterThan(rep.pixelsWide, 0)
        XCTAssertGreaterThan(rep.pixelsHigh, 0)
    }

    func testHistoryPreviewWindowControllerImagePrintingState() throws {
        let textItem = HistoryItem(id: UUID(), kind: .text, text: "hello", capturedAt: Date(),
                                   imageRelativePath: nil, contentHash: nil, files: [])
        let imageItem = HistoryItem(id: UUID(), kind: .image, text: "", capturedAt: Date(),
                                    imageRelativePath: "test.png", contentHash: nil, files: [])

        let controller = HistoryPreviewWindowController.shared
        controller.close()
        XCTAssertFalse(controller.canPrintCurrentImage)
        XCTAssertNil(controller.currentItem)

        let model = AppModel()
        let palette = PaperTheme.macosNative.palette
        controller.show(item: textItem, model: model, palette: palette)
        XCTAssertFalse(controller.canPrintCurrentImage)

        controller.show(item: imageItem, model: model, palette: palette)
        XCTAssertTrue(controller.canPrintCurrentImage)

        controller.close()
        XCTAssertFalse(controller.canPrintCurrentImage)
        XCTAssertNil(controller.currentItem)
    }

    func testDetectedWindowCandidateDisplayNameFormatting() throws {
        let plain = DetectedWindowCandidate(id: 1, appName: "Finder", windowTitle: "", rect: CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertEqual(plain.displayName, "Finder")

        let sameTitle = DetectedWindowCandidate(id: 2, appName: "Safari", windowTitle: "Safari", rect: CGRect(x: 0, y: 0, width: 300, height: 300))
        XCTAssertEqual(sameTitle.displayName, "Safari")

        let withTitle = DetectedWindowCandidate(id: 3, appName: "Google Chrome", windowTitle: "GitHub", rect: CGRect(x: 0, y: 0, width: 400, height: 400))
        XCTAssertEqual(withTitle.displayName, "Google Chrome — GitHub")
    }

    func testDetectedWindowCandidateDetectionAndBounds() throws {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenLocalBounds = CGRect(origin: .zero, size: screen.frame.size)
        let candidates = DetectedWindowCandidate.detectCandidates(for: screen)

        for candidate in candidates {
            XCTAssertGreaterThanOrEqual(candidate.rect.width, 80)
            XCTAssertGreaterThanOrEqual(candidate.rect.height, 80)
            XCTAssertTrue(screenLocalBounds.intersects(candidate.rect), "Candidate rect \(candidate.rect) must intersect screen bounds \(screenLocalBounds)")
        }

        if let firstCandidate = candidates.first {
            let filtered = DetectedWindowCandidate.detectCandidates(for: screen, excludingWindowNumber: Int(firstCandidate.id))
            XCTAssertFalse(filtered.contains(where: { $0.id == firstCandidate.id }), "Excluding window number should filter it out")
        }
    }
}

