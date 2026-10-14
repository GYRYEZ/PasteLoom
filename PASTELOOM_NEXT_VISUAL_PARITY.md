# PasteLoom Next visual and feature parity

The 22 user-provided screenshots are the visual and interaction reference for PasteLoom Next. They describe observable behavior; this project remains an independent implementation. The screenshots do not authorize reading or copying the old application's source, resources, project files, scripts, or history.

## Visual system

- A narrow floating history drawer with a soft blue paper surface, rounded outer corners, a compact header, search controls, and vertically stacked white paper cards.
- Cards show the source application, time, content type and metadata, a content preview, and actions. Images preserve aspect ratio. The drawer never clips its final card.
- Settings use a wide rounded window, a horizontal area selector, a page sidebar, and grouped white setting cards. Active controls use a calm blue accent.
- Six paper themes, light/dark/system appearance, and left/right/top/bottom drawer placement are user choices.
- UI copy is Chinese where the screenshots are Chinese. Development identity remains PasteLoom Next with bundle ID `com.gyryez.pasteloom.next`.

## Screenshot feature inventory

| Reference | Behavior | Current state |
| --- | --- | --- |
| History drawer | Text, URL, image and file cards, thumbnail, preview, copy back | Implemented; visual refinement ongoing |
| History actions | Favorites, pin, tags, trash and restore | Implemented with persisted metadata; multi-select adds batch favorite, pin, trash and restore |
| Search | Keyword and tag search | Implemented with combinable type, source-name, and recent-seven-day filters; broader date-range and saved filters pending |
| Paper themes and layout | Six themes, appearance, drawer edges | Implemented; multi-display visual validation pending |
| General window controls | Edge hover, login launch, Dock/menu bar choice, screen sharing behavior, sounds | Pending |
| Panel and previews | List/grid modes, hover previews, video preview | List/grid implemented for history and Quick Paste; hover and video preview pending |
| Shortcut settings | Current shortcut and Accessibility status | Quick Paste shortcut is editable with conflict rollback and default restore; other actions pending |
| Screenshot capture | Region/window capture, quick clipboard copy, self-window exclusion | Pending |
| Annotation board | Shapes, pen, text, mosaic, undo, export | Pending |
| Screenshot output | PNG and other formats, history insertion, OCR, file backup | Pending |
| Rules and scripts | Rule editor, execution, import, audit trail | Pending |
| AI / MCP | Local server, tool permissions, client configuration | Pending; must be opt-in |
| Capture and filtering | URL cleaning, excluded apps/types, text rules | Optional URL cleaning and type exclusions implemented for new captures; app and text exclusions pending |
| Content protection | Sensitive-content redaction and guarded export | Pending |
| Merge | Multi-selection and content/image merge | Multi-selection and bounded batch bar implemented; content/image merge pending |
| Sync | Explicitly enabled device sync | Pending; default off |
| Retention and statistics | Trash aging, copy counts, per-type retention | Pending |
| Import and export | JSON backup/import and destructive clear | Pending; must preserve existing data |

## Implementation order

1. Finish the history and settings shell and persist its working controls. Verify existing clipboard behavior, schema migration, and desktop rendering.
2. Add history filters, source/date metadata, multi-selection, preview modes, retention, privacy controls, and backup. Each new setting becomes visible as an active control only when its behavior is implemented and tested.
3. Build screenshot capture and annotation as a separate service and window, with independent permission checks and file storage. Then add OCR as an optional local index.
4. Add rules/scripts and external integrations with explicit permissions, audit records, and failure isolation. Add sync only after a defined protocol and conflict policy exist.

No pending control is presented as enabled merely to match a screenshot. A full visual and functional acceptance pass requires every item in the inventory to be implemented and tested on the desktop.
