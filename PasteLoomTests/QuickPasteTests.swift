import AppKit
import XCTest
@testable import PasteLoom

@MainActor
final class QuickPasteTests: XCTestCase {
    func testTagMatchSettingPersistsAndDefaultsSafely() {
        let suite = "PasteLoomTagSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(TagMatchMode.load(from: defaults), .any)
        defaults.set(TagMatchMode.all.rawValue, forKey: "tagMatchMode")
        let reopened = UserDefaults(suiteName: suite)!
        XCTAssertEqual(TagMatchMode.load(from: reopened), .all)
        reopened.set("invalid", forKey: "tagMatchMode")
        XCTAssertEqual(TagMatchMode.load(from: reopened), .any)
    }

    func testShortcutRecordingRequiresModifierAndKeepsPhysicalKey() {
        let valid = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                     modifierFlags: [.command, .option], timestamp: 0,
                                     windowNumber: 0, context: nil, characters: "k",
                                     charactersIgnoringModifiers: "k", isARepeat: false,
                                     keyCode: 40)!
        let parsed = GlobalShortcut.from(valid)
        XCTAssertEqual(parsed?.keyCode, 40)
        XCTAssertEqual(parsed?.displayName, "⌥⌘K")
        let ordinary = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                        modifierFlags: [], timestamp: 0,
                                        windowNumber: 0, context: nil, characters: "k",
                                        charactersIgnoringModifiers: "k", isARepeat: false,
                                        keyCode: 40)!
        XCTAssertNil(GlobalShortcut.from(ordinary))
    }

    func testShortcutSettingSurvivesReloadWithoutChangingUserPreferences() {
        let suite = "PasteLoomShortcutTests.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        XCTAssertEqual(GlobalShortcut.load(from: store), .quickPaste)
        let custom = GlobalShortcut(keyCode: 40, modifiers: 2048 | 256, displayName: "⌥⌘K")
        custom.save(to: store)
        XCTAssertEqual(GlobalShortcut.load(from: store), custom)
    }

    func testKeyboardCommandsKeepTypingSeparateFromNavigation() {
        XCTAssertEqual(QuickPasteKeyAction(keyCode: 53), .escape)
        XCTAssertEqual(QuickPasteKeyAction(keyCode: 125), .moveDown)
        XCTAssertEqual(QuickPasteKeyAction(keyCode: 126), .moveUp)
        XCTAssertEqual(QuickPasteKeyAction(keyCode: 36), .confirm)
        XCTAssertEqual(QuickPasteKeyAction(keyCode: 76), .confirm)
        XCTAssertEqual(QuickPasteKeyAction(keyCode: 0), .passthrough)
    }

    func testSelectionMovesWithinBoundsAndQueryResetsSelection() async {
        let history = FakeQuickHistory()
        let model = QuickPasteViewModel(history: history)
        model.open()
        await settle(model, count: 3)
        XCTAssertEqual(model.selectedIndex, 0)
        model.moveSelection(by: -1)
        XCTAssertEqual(model.selectedIndex, 0)
        model.moveSelection(by: 1)
        model.moveSelection(by: 1)
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedIndex, 2)
        XCTAssertEqual(model.selectedItem?.text, "gamma")

        model.updateQuery("beta")
        XCTAssertNil(model.selectedItem)
        await settle(model, count: 1)
        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertEqual(model.selectedItem?.text, "beta")
        model.updateQuery("missing")
        await settle(model, count: 0)
        XCTAssertNil(model.selectedItem)
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedIndex, 0)
    }

    func testEscapeResetKeepsClipboardUntouched() async {
        let history = FakeQuickHistory()
        let model = QuickPasteViewModel(history: history)
        model.open()
        await settle(model, count: 3)
        model.updateQuery("beta")
        await settle(model, count: 1)
        model.reset()
        XCTAssertEqual(model.query, "")
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertEqual(model.selectedIndex, 0)
        XCTAssertEqual(history.copyCount, 0)
    }

    func testDecisionCoversCopyPermissionTargetAndActivation() {
        XCTAssertEqual(QuickPasteDecision.make(autoPasteEnabled: false, accessibilityGranted: false,
                                               targetValid: false, targetActivated: false), .copyOnly)
        XCTAssertEqual(QuickPasteDecision.make(autoPasteEnabled: true, accessibilityGranted: false,
                                               targetValid: true, targetActivated: true), .permissionRequired)
        XCTAssertEqual(QuickPasteDecision.make(autoPasteEnabled: true, accessibilityGranted: true,
                                               targetValid: false, targetActivated: false), .noTarget)
        XCTAssertEqual(QuickPasteDecision.make(autoPasteEnabled: true, accessibilityGranted: true,
                                               targetValid: true, targetActivated: false), .activationFailed)
        XCTAssertEqual(QuickPasteDecision.make(autoPasteEnabled: true, accessibilityGranted: true,
                                               targetValid: true, targetActivated: true), .sendPaste)
    }

    func testCopyOnlyAndUnavailableAutoPasteNeverPostPaste() async {
        let history = FakeQuickHistory()
        let accessibility = FakeAccessibility()
        let focus = FakeFocus()
        let injection = FakeAutoPaste()
        let action = QuickPasteActionService(history: history, accessibility: accessibility,
                                             focus: focus, autoPaste: injection)
        let item = history.items[0]
        var dismissCount = 0
        let copy = await action.perform(item: item, autoPasteEnabled: false, target: nil) { dismissCount += 1 }
        XCTAssertEqual(copy, .copied)
        XCTAssertEqual(dismissCount, 1)
        XCTAssertEqual(history.copyCount, 1)
        XCTAssertEqual(injection.pasteCount, 0)

        let blocked = await action.perform(item: item, autoPasteEnabled: true, target: nil) { dismissCount += 1 }
        XCTAssertEqual(blocked, .copiedPermissionRequired)
        XCTAssertEqual(dismissCount, 2)
        XCTAssertEqual(injection.pasteCount, 0)

        accessibility.granted = true
        let noTarget = await action.perform(item: item, autoPasteEnabled: true, target: nil) { dismissCount += 1 }
        XCTAssertEqual(noTarget, .copiedNoTarget)
        XCTAssertEqual(dismissCount, 3)
        XCTAssertEqual(history.copyCount, 3)
        XCTAssertEqual(injection.pasteCount, 0)
    }

    private func settle(_ model: QuickPasteViewModel, count: Int) async {
        for _ in 0..<100 where model.results.count != count { await Task.yield() }
        XCTAssertEqual(model.results.count, count)
    }
}

@MainActor
private final class FakeQuickHistory: QuickPasteHistoryProviding {
    let items = ["alpha", "beta", "gamma"].map {
        HistoryItem(id: UUID(), kind: .text, text: $0, capturedAt: Date(),
                    imageRelativePath: nil, contentHash: nil, files: [])
    }
    var copyCount = 0

    func quickSearch(_ query: String, limit: Int) async throws -> [HistoryItem] {
        Array(items.filter { query.isEmpty || $0.text.contains(query) }.prefix(limit))
    }
    func copyForQuickPaste(_ item: HistoryItem) async throws { copyCount += 1 }
    func thumbnail(for item: HistoryItem, maxPixelSize: Int) async -> Data? { nil }
}

@MainActor
private final class FakeAccessibility: AccessibilityChecking {
    var granted = false
    var isTrusted: Bool { granted }
    func openSettings() {}
}

@MainActor
private final class FakeFocus: FocusRestoring {
    func captureTarget() -> FocusTarget? { nil }
    func restore(_ target: FocusTarget?) async -> Bool { false }
}

@MainActor
private final class FakeAutoPaste: AutoPasting {
    var pasteCount = 0
    func paste(into target: FocusTarget) -> Bool {
        pasteCount += 1
        return true
    }
}
