import AppKit
import XCTest
@testable import PasteLoom

@MainActor
final class Stage2Tests: XCTestCase {
    func testAllShortcutActionsHaveDistinctDefaultKeys() {
        var seen: Set<String> = []
        for action in ShortcutAction.allCases {
            let shortcut = action.defaultShortcut
            XCTAssertFalse(seen.contains(shortcut.displayName), "Default shortcut \(shortcut.displayName) should be distinct")
            seen.insert(shortcut.displayName)
            XCTAssertFalse(action.displayName.isEmpty)
        }
    }

    func testShortcutActionStorageAndReset() {
        let suite = "PasteLoomStage2Shortcuts.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }

        // Test mainWindow
        XCTAssertEqual(GlobalShortcut.load(for: .mainWindow, from: store), ShortcutAction.mainWindow.defaultShortcut)
        let custom = GlobalShortcut(keyCode: 15, modifiers: 2048 | 256, displayName: "⌥⌘R")
        custom.save(for: .mainWindow, to: store)
        XCTAssertEqual(GlobalShortcut.load(for: .mainWindow, from: store), custom)

        GlobalShortcut.clear(for: .mainWindow, in: store)
        XCTAssertEqual(GlobalShortcut.load(for: .mainWindow, from: store), ShortcutAction.mainWindow.defaultShortcut)
    }

    func testShortcutConflictDetectionPreventsDuplicateInAppBindings() {
        let suite = "PasteLoomConflictTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }

        let service = GlobalShortcutService()
        // Try to assign the default quickPaste shortcut (⌥⌘V) to mainWindow
        let collisionShortcut = ShortcutAction.quickPaste.defaultShortcut
        let result = service.updateShortcut(collisionShortcut, for: .mainWindow, store: store)

        switch result {
        case .failure(.inAppConflict(let conflictingAction)):
            XCTAssertEqual(conflictingAction, .quickPaste)
        default:
            XCTFail("Expected in-app conflict with quickPaste, but got \(result)")
        }
    }

    func testQuickPasteKeyActionSpaceTogglesSelect() {
        XCTAssertEqual(QuickPasteKeyAction(keyCode: 49), .toggleSelect)
        XCTAssertEqual(QuickPasteKeyAction(keyCode: 53), .escape)
        XCTAssertEqual(QuickPasteKeyAction(keyCode: 125), .moveDown)
        XCTAssertEqual(QuickPasteKeyAction(keyCode: 126), .moveUp)
        XCTAssertEqual(QuickPasteKeyAction(keyCode: 36), .confirm)
        XCTAssertEqual(QuickPasteKeyAction(keyCode: 76), .confirm)
        XCTAssertEqual(QuickPasteKeyAction(keyCode: 1), .passthrough)
    }

    func testQuickPasteMultiSelectionMaintainsOrderAndToggles() async {
        let history = FakeStage2QuickHistory()
        let model = QuickPasteViewModel(history: history)
        model.open()
        for _ in 0..<50 where model.results.count != 3 { await Task.yield() }

        XCTAssertEqual(model.results.count, 3)
        let first = model.results[0]
        let second = model.results[1]
        let third = model.results[2]

        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertFalse(model.isSelected(first))

        // Select third, then first
        model.toggleSelection(for: third)
        XCTAssertTrue(model.isSelected(third))
        XCTAssertEqual(model.selectedIDs, [third.id])

        model.toggleSelection(for: first)
        XCTAssertTrue(model.isSelected(first))
        XCTAssertEqual(model.selectedIDs, [third.id, first.id])

        // Verify itemsToPaste reflects selection order: [third, first]
        let pasteItems = model.itemsToPaste
        XCTAssertEqual(pasteItems.count, 2)
        XCTAssertEqual(pasteItems[0].id, third.id)
        XCTAssertEqual(pasteItems[1].id, first.id)

        // Deselect third
        model.toggleSelection(for: third)
        XCTAssertFalse(model.isSelected(third))
        XCTAssertEqual(model.selectedIDs, [first.id])

        // Clear multi selection
        model.clearMultiSelection()
        XCTAssertTrue(model.selectedIDs.isEmpty)
    }

    func testQuickPasteNewQueryClearsMultiSelection() async {
        let history = FakeStage2QuickHistory()
        let model = QuickPasteViewModel(history: history)
        model.open()
        for _ in 0..<50 where model.results.count != 3 { await Task.yield() }

        model.toggleSelection(for: model.results[0])
        XCTAssertEqual(model.selectedIDs.count, 1)

        model.updateQuery("item")
        XCTAssertTrue(model.selectedIDs.isEmpty)
    }

    func testEdgeHoverPointDetection() {
        let frame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        // Left
        XCTAssertTrue(EdgeHoverMonitor.isPointNearEdge(NSPoint(x: 2, y: 500), in: frame, side: "left"))
        XCTAssertFalse(EdgeHoverMonitor.isPointNearEdge(NSPoint(x: 20, y: 500), in: frame, side: "left"))

        // Right
        XCTAssertTrue(EdgeHoverMonitor.isPointNearEdge(NSPoint(x: 1918, y: 500), in: frame, side: "right"))
        XCTAssertFalse(EdgeHoverMonitor.isPointNearEdge(NSPoint(x: 1800, y: 500), in: frame, side: "right"))

        // Top
        XCTAssertTrue(EdgeHoverMonitor.isPointNearEdge(NSPoint(x: 500, y: 1078), in: frame, side: "top"))
        XCTAssertFalse(EdgeHoverMonitor.isPointNearEdge(NSPoint(x: 500, y: 1000), in: frame, side: "top"))

        // Bottom
        XCTAssertTrue(EdgeHoverMonitor.isPointNearEdge(NSPoint(x: 500, y: 2), in: frame, side: "bottom"))
        XCTAssertFalse(EdgeHoverMonitor.isPointNearEdge(NSPoint(x: 500, y: 20), in: frame, side: "bottom"))
    }

    func testCursorAssistantTriplePressDetection() {
        let now = Date()
        let rapidTimestamps = [
            now.addingTimeInterval(-0.4),
            now.addingTimeInterval(-0.2),
            now
        ]
        XCTAssertTrue(CursorAssistantMonitor.shouldTrigger(timestamps: rapidTimestamps))

        let slowTimestamps = [
            now.addingTimeInterval(-2.0),
            now.addingTimeInterval(-1.0),
            now
        ]
        XCTAssertFalse(CursorAssistantMonitor.shouldTrigger(timestamps: slowTimestamps))
    }
}

@MainActor
private final class FakeStage2QuickHistory: QuickPasteHistoryProviding {
    let items = ["item-A", "item-B", "item-C"].map {
        HistoryItem(id: UUID(), kind: .text, text: $0, capturedAt: Date(),
                    imageRelativePath: nil, contentHash: nil, files: [])
    }

    func quickSearch(_ query: String, limit: Int) async throws -> [HistoryItem] {
        items
    }
    func copyForQuickPaste(_ item: HistoryItem) async throws {}
    func thumbnail(for item: HistoryItem, maxPixelSize: Int) async -> Data? { nil }
}
