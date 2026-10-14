# PasteLoom

**PasteLoom is a native macOS clipboard history app.** It keeps copied content in a local searchable library, with quick access from an edge drawer, a menu bar panel, and a keyboard-driven Quick Paste panel.

> **Development build:** PasteLoom is under active development. Some system-level workflows depend on macOS permissions and need hands-on validation. This source repository is not a signed or notarized release. Keep other copies of important clipboard content.

## What it does

- Captures text, URLs, images, files, multiple files, and supported rich-text or video-file representations from the system pasteboard.
- Stores history and image assets locally using SQLite and the user's Application Support folder.
- Searches history, including local semantic matching, and supports content filters, tags, favorites, and pinned items.
- Copies saved entries back to the system pasteboard. Quick Paste also offers keyboard navigation and optional Auto Paste.
- Provides a menu bar history panel and an edge-attached main drawer with list and grid layouts and appearance themes.
- Captures screenshots and includes an annotation editor with crop, shapes, arrows, lines, pen, text, mosaic, undo/redo, save, and copy actions.
- Includes local OCR, backup/import/export, retention and privacy settings. Advanced integration areas such as automation, MCP, widgets, and sync are experimental and may be incomplete; see [the current project status](PASTELOOM_NEXT_CURRENT_STATUS.md) and [feature matrix](PASTELOOM_NEXT_FEATURE_GAP_MATRIX.md).

Feature presence in the interface does not guarantee that every workflow is production-ready. The project reports document the scope and limits of validation.

## Requirements

- macOS 14 or later
- Xcode with the macOS SDK
- Apple Silicon or Intel Mac for a native build. A universal release artifact is not currently provided by this source checkout.

The app bundle identifier is `com.gyryez.pasteloom`.

## Build and test

```sh
xcodebuild -project PasteLoom/PasteLoom.xcodeproj \
  -scheme PasteLoom \
  -destination 'platform=macOS' \
  build

xcodebuild -project PasteLoom/PasteLoom.xcodeproj \
  -scheme PasteLoom \
  -destination 'platform=macOS' \
  test
```

Or open `PasteLoom/PasteLoom.xcodeproj` in Xcode and run the `PasteLoom` scheme.

## Permissions and privacy

Clipboard history may contain private or sensitive information. History is stored locally by default; review capture exclusions and privacy settings before use. Optional operations such as Auto Paste and screen capture require macOS permissions. PasteLoom does not bypass Accessibility, Screen Recording, or other system privacy controls.

The application stores its database and image assets in the current user's Application Support directory. Do not upload a live user database or personal clipboard history when filing an issue.

## Documentation

- [中文使用说明与项目介绍](PasteLoom_Complete_Guide.md)
- [Current implementation status](PASTELOOM_NEXT_CURRENT_STATUS.md)
- [Feature gap matrix](PASTELOOM_NEXT_FEATURE_GAP_MATRIX.md)
- [Implementation plan](PASTELOOM_NEXT_IMPLEMENTATION_PLAN.md)
- [Product and behavior specifications](PASTELOOM_PRODUCT_SPEC.md), [UI specification](PASTELOOM_UI_SPEC.md), and [settings specification](PASTELOOM_SETTINGS_SPEC.md)

The reports and specifications are development records. Some are historical snapshots and may describe earlier commits; consult the current status document for the latest verification scope.

## Release status

This repository is for development and evaluation. No Developer ID signed/notarized release is included. A macOS Gatekeeper warning may appear for locally built or unsigned copies. Intel and Apple Silicon release compatibility must be verified against the specific release artifact, not inferred from the source code alone.

## License

No license has been selected or included yet. Until the project owner adds a license, public visibility of the repository does not grant permission to copy, modify, distribute, or sublicense the code. Please do not treat this project as open-source licensed software.

## Project identity

PasteLoom is developed as a new, independent implementation using public macOS APIs and the product specifications in this repository. It does not include source code copied from the earlier PasteLoom/Clipth project.
