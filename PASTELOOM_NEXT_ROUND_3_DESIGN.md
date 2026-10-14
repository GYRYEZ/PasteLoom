# PasteLoom Next Round 3 — Quick Paste design

## Boundaries

- `GlobalShortcutService` owns Carbon `RegisterEventHotKey` registration for the default `⌥⌘V`. The key combination is a value so a later settings flow can replace it. No third-party dependency is needed.
- `QuickPasteCoordinator` owns presentation, dismissal, action sequencing, and the target application captured before showing the panel. It does not poll the clipboard.
- `QuickPastePanel` owns the transient AppKit window and positioning on the screen containing the pointer, clamped to the screen's visible frame. Resigning key or pressing Escape closes it.
- `QuickPasteViewModel` owns a small result set, search text, keyboard selection, and the user's Copy Only or Auto Paste choice. It asks the existing search layer for results; no database or pasteboard operation lives in the SwiftUI view.
- `FocusRestorationService` records and reactivates the original `NSRunningApplication` after the panel closes.
- `AccessibilityService` checks the new app's own trust without repeated system prompts and opens the relevant System Settings page on explicit user action.
- `AutoPasteService` posts Command-V through CoreGraphics only after permission is present and the original application is foreground again. The existing clipboard adapter writes the selected original content type before this action.

## Interaction behavior

The shortcut opens an immediately focused search field. Up/Down move through results; Return follows the Auto Paste setting, which defaults to off. A visible Copy Only action always writes the selected item and restores the original app. Without Accessibility permission, Return uses Copy Only and the panel explains how to grant permission and paste manually. Escape and an outside click dismiss the panel. The main history window and clipboard monitor remain independent.

## Data and security

Quick Paste reuses `HistoryItem`, `LocalHistorySearch`, and the existing typed Copy Back path. It adds no schema and no network calls. The app must check its own Accessibility trust; the stable app's authorization is irrelevant. Clipboard writes from Quick Paste continue through `ClipboardService.copyToPasteboard`, preserving self-write suppression.
