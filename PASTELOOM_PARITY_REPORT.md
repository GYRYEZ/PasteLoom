# PasteLoom Product Parity Report — Phase A

Golden Master observed through the running app's visible UI and accessibility tree. Old source, project files, scripts, resources and database were not accessed. The implementation is independent.

| Area | Old PasteLoom | PasteLoom Next after Phase A | Status |
|------|---------------|-----------------------------|--------|
| Main Window | Narrow branded clipboard workspace with a prominent search and paper-like cards | Branded SwiftUI workspace, top search/status, bounded content cards | PARTIAL |
| History Cards | Source app, time, type and context actions; image thumbnail | Distinct text, URL, image and file cards with time, metadata, copy and preview; source app metadata awaits Phase B | PARTIAL |
| Search | Full-text, semantic and tag modes plus advanced filters | Immediate local search for text, URL/domain and filename; empty state; existing search layer reused | PARTIAL |
| Quick Paste | ⌥⌘V shown in settings; compact list/grid options | Compact keyboard-first panel styled with brand header and material search field; real desktop invocation remains unverified | PARTIAL |
| Settings | Extensive in-window directory for appearance, windows, shortcuts and panel/preview | Native tabs for General, Clipboard, Quick Paste, Appearance and About, showing only working controls | PARTIAL |
| Preview | Native Quick Look text preview observed | Full text, URL information/open, large image, native Quick Look for available files | PARTIAL |
| Menu Bar | Menu bar entry visible in old settings; live menu behavior not conclusively observed | Native `MenuBarExtra` with History, Quick Paste, Pause/Resume, Settings, Quit; click behavior awaits desktop confirmation | PARTIAL |
| Dark Mode | System/Light/Dark settings observed | System/Light/Dark applied to Settings, main workspace and Quick Paste view; main and Settings dark screenshots inspected | IMPROVED |
| Edge Dock | Edge attachment and hover controls observed in settings | Phase C | NOT IMPLEMENTED |
| Cursor Assistant | Triple-Shift control observed in settings | Phase C | NOT IMPLEMENTED |
| OCR | Image text recognition action observed | Phase C | NOT IMPLEMENTED |
| MCP | Not confirmed by black-box inspection | Later phase | NOT IMPLEMENTED |
| Sync | Not confirmed by black-box inspection | Later phase | NOT IMPLEMENTED |

## Validation

- `xcodebuild test`: 19 passed, 0 failed. This includes existing capture, typed Copy Back, search, persistence and migration checks.
- Existing live SQLite database: `PRAGMA quick_check = ok`; no schema changes and no history deletion.
- Runtime: new app main workspace and structured Settings observed in light mode; main workspace and Settings observed in dark mode, then appearance restored to System.
- Search: `Tudor PELAGOS` narrowed live history to two items. Search for `example.com` showed URL cards; `txt` showed file cards; `.pdf` showed the empty result state.
- Preview: text and URL detail sheets, large image sheet, and native Quick Look for an available `sample-file.txt` observed.
- Not yet validated through desktop interaction: menu bar icon click actions, Quick Paste shortcut when old/new apps both run, Auto Paste target focus and Cmd+V, multi-display behavior, all legacy visual variants. Round 3 manual Auto Paste validation remains pending.

## Remaining parity work

Phase B: source app metadata and source search, Favorites/Pin, tags if retained, complete Quick Paste and Auto Paste desktop acceptance. Phase C: edge behavior, cursor assistant, text actions, privacy controls and OCR. Phase D: evaluate semantic search, MCP, Widget, Sync and updates. Old MCP and Sync behavior: **NEEDS USER CONFIRMATION** or later black-box observation.

## Git

Commit: included with `feat: align PasteLoom Next product experience`.

No release tag or push. The existing `pasteloom-next-round2.5` tag and Round 3 commit remain unchanged.

## Old Source Accessed

NO
