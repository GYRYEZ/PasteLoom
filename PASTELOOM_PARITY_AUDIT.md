# PasteLoom Product Parity Audit

Scope: visual and behavioral black-box inspection of the running `com.gyryez.pasteloom` application, compared with the independent PasteLoom Next source and running app. No old project files, assets, database, or implementation were opened.

| Area | Old PasteLoom observed | PasteLoom Next before Phase A | Phase A direction |
|---|---|---|---|
| App startup | Narrow, custom clipboard workspace was visible; status-bar behavior needs further direct observation | Ordinary SwiftUI window; separate basic Settings window | Add a persistent menu bar entry and branded workspace |
| Main window | Branded top row, search modes, history/favorites controls, textured cards | Standard List, searchable toolbar, plain rows | Build card workspace and primary search in header |
| History cards | Source application and time in card header; type metadata and actions in footer; image thumbnail | Text/URL/image/file rows with small icon and buttons | Distinct content cards with bounded previews |
| Search | Prominent search; Full Text, Semantic, Tag modes; app/date filter syntax shown in help | Local keyword search for content, URL and file name | Keep one local search path; defer semantic/tag modes |
| Settings | Dedicated in-window directory; Appearance/Layout, Window/Behavior, Panel/Preview; separate Shortcuts group | Small form | Structured settings for available Next features |
| Quick Paste | Shortcut settings display ⌥⌘V; list/grid preference and linger preview setting visible | Functional floating panel, plain rows; real hotkey/paste still awaiting user validation | Polish compact keyboard-first visual |
| Preview | Text preview opens a separate native Quick Look window | Text/image/URL/file SwiftUI sheet | Improve type previews; prefer native file Quick Look |
| Appearance | System/Light/Dark controls; multiple paper themes | System appearance only | Expose System/Light/Dark with subtle brand material |
| Window behavior | Edge hover, edge attachment, cursor assistant and menu icon toggles visible in settings | Ordinary window | Later phases; do not claim parity in Phase A |
| Privacy | Capture pause button visible | Capture toggle | Keep pause readily accessible |
| Favorites / Pin / Tags | Main card buttons and search modes visible | Absent | Phase B with independent schema migration |
| OCR | Image card has text recognition action | Absent | Phase C |
| Semantic / MCP / Sync | Semantic search control visible; MCP and Sync not confirmed by black-box observation | Absent | Later phases; NEEDS USER CONFIRMATION for unobserved behavior |

The running Next process observed during audit showed an older Settings build. Source at `aedfeba` is the implementation baseline used for development. Real shortcut, Auto Paste, old status-bar panel, old URL/file previews, dark mode, and multi-display behavior were not conclusively observed during this audit; their parity remains unverified.
