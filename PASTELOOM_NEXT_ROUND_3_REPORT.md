# PasteLoom Next Round 3 Report

**Round 3 Implementation Complete**  
**Manual Auto Paste Validation Pending**

## Global Shortcut implementation

`GlobalShortcutService` wraps Apple's Carbon `RegisterEventHotKey` and registers once during app startup. Re-registration removes the previous hotkey and event handler first. No third-party dependency was added. The shortcut is a `GlobalShortcut` value so a later settings flow can replace it without moving keyboard logic into a View. A registration error is displayed in Settings.

## Default shortcut

`⌥⌘V` (Option-Command-V), using virtual key code 9 and Carbon command/option modifiers. Actual invocation from another app awaits manual desktop validation.

## Quick Paste architecture

`QuickPasteCoordinator` owns the transient session. `QuickPasteViewModel` reuses `LocalHistorySearch` through `AppModel`, handles query and selection, and clears stale results immediately on query changes. `QuickPasteActionService` decides Copy Only versus Auto Paste and orders copy, dismissal, target restoration, and paste injection. `GlobalShortcutService`, `FocusRestorationService`, `AutoPasteService`, and `AccessibilityService` wrap their respective macOS boundaries. The existing `ClipboardService` and its 0.20-second monitor were not changed.

## Panel implementation

An `NSPanel` hosts SwiftUI content. A new session resets search, selection and status. A local key monitor handles Up, Down, Return and Escape while the panel is key. A second shortcut invocation toggles it closed. Resigning key closes it after an outside click. The panel is positioned on the screen containing the pointer, near the upper-middle of that screen's visible frame and clamped inside its edges.

## Search

The panel calls the existing search layer with a 40-result limit. Results load asynchronously; old results clear as soon as the query changes, so Return cannot select an item from a stale query. Image thumbnails use the existing bounded thumbnail store and load on demand.

## Keyboard navigation

Up and Down move a clamped selection. Return follows the Auto Paste setting. Escape closes and resets the panel without writing to the clipboard or posting Cmd+V. A visible `仅复制` button always selects Copy Only.

## Previous app tracking

Before presenting the panel, `FocusRestorationService` captures the foreground `NSRunningApplication`, its process identifier and bundle identifier. The coordinator retains that target only for the current session, then clears it on close. PasteLoom Next itself is rejected as a target.

## Focus restoration

The panel closes before target activation. The service calls the public `NSRunningApplication.activate()` API and checks `NSWorkspace.frontmostApplication` for the captured PID, retrying at 40 ms intervals for at most 600 ms. If the target is absent or activation does not succeed, no paste key event is posted.

## Accessibility

The new app checks its own `AXIsProcessTrusted()` status without triggering a system prompt. Settings show the current status, provide an explicit System Settings link, and refresh when the app becomes active. Search and Copy Only do not require the permission. When Auto Paste is enabled without permission, the panel explains that Return will only copy.

## Copy Only

The selected item uses the existing typed Copy Back path for text, URL, image, single file or multiple files. The panel then closes and attempts to restore the previous app. No Cmd+V is posted. The existing self-write suppression remains in `ClipboardService`.

## Auto Paste

Auto Paste defaults to off and can be toggled in Settings. When enabled, the action copies the selected type, closes the panel, restores and verifies the original foreground app, then posts Command-V through CoreGraphics. Invalid target, missing Accessibility permission or failed activation causes a Copy Only fallback. A unit test verifies these decisions; **actual system Cmd+V delivery is not asserted by unit tests** and remains pending manual validation.

## Multi-display

The positioning code chooses the screen containing the pointer and only falls back to the main/first screen if no screen contains it. **Multi-display: NOT TESTED.**

## Automated tests

Debug macOS `xcodebuild test` passed: **19 passed, 0 failed** (14 existing plus 5 Quick Paste tests). New tests cover selection movement and bounds, query reset and stale-result prevention, keyboard command mapping, Escape state reset without a copy, Copy Only behavior, Accessibility fallback, invalid target fallback, and the Auto Paste decision table. Existing typed pasteboard, self-write suppression, capture classification, search, migration and persistence tests still pass. The actual app database returned `ok` from `PRAGMA quick_check`.

## Manual desktop validation

**PENDING USER VALIDATION.** No Quick Paste or Auto Paste desktop result is marked PASS yet. The user should check shortcut opening from TextEdit, immediate typing, Up/Down/Return/Escape, Copy Only using `PASTELOOM_QUICK_COPY_TEST` and `pbpaste`, and Auto Paste into a TextEdit insertion point using `PASTELOOM_AUTO_PASTE_TEST` after granting this new app Accessibility permission. The no-permission path, outside-click dismissal, 30 open/close cycles, and multi-display placement (if available) also remain to be checked. If Auto Paste fails, classify it as A shortcut, B panel, C selection/search, D pasteboard write, E panel dismissal, F target restoration, G Cmd+V posting, or H target response.

## Existing feature regression

Automated text/URL/image/file/multi-file classification, typed Copy Back, self-write suppression, search, persistence and migration tests passed. Real desktop capture, Pause/Resume, and extended 30-cycle panel stability checks are pending the user's manual session. The Clipboard polling implementation and interval were left untouched.

## Performance observation

New Quick Paste UI performance and 30-cycle CPU/memory behavior are **NOT TESTED** on the desktop. The existing image thumbnail cache remains bounded. No performance PASS is claimed.

## Known limitations

- Shortcut customization UI is not exposed yet; the shortcut value and registration API permit a later settings implementation.
- Auto Paste depends on this development app's own Accessibility authorization and the target app accepting Command-V. An unsigned Debug build may need to be reauthorized after its identity changes.
- A target that disappears or cannot be reactivated falls back to Copy Only. No keystroke is injected into an unknown or PasteLoom Next process.
- `NSPasteboard` still holds only the latest content; this round does not alter capture reliability or the polling interval.

## Git

Implementation commit: this document is included in `feat: add Quick Paste and Auto Paste`.  
Round 2.5 baseline: `21eb423` / `pasteloom-next-round2.5` (preserved).  
Round 3 tag: **NOT CREATED — manual Auto Paste validation pending.**  
No push.

## Old Source Accessed

NO
