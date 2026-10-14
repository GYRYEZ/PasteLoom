# PasteLoom Next Round 2 Report

## Schema Migration

The existing SQLite v1 database is migrated in place to `user_version = 2` inside one transaction. The migration retains every v1 row and ID, adds `kind` (default `text`), `asset_path`, `content_hash`, and `search_text`, backfills `search_text` from the original `text`, and creates the ordered `file_references` child table. A failed migration rolls back. The database is never rebuilt or deleted. A consistent v1 backup was made before desktop validation; it had 3 text rows and passed `PRAGMA integrity_check`.

The actual app database migrated to v2. After the desktop run and app restart, the 3 original text rows remain, and `PRAGMA integrity_check` returns `ok`.

## Content Types

The domain model now supports `text`, `url`, `image`, and `file`. One pasteboard change produces at most one logical record. Classification priority is file URLs, image bytes, HTTP(S) URL, then plain text. This preserves Finder file semantics when an item also advertises a preview representation. Text records and the original text column remain readable.

## URL

A complete HTTP(S) URL is retained without fetching metadata. The list shows the URL and its domain. The URL and domain are searchable. Copy Back advertises both `public.url` and plain text with the original full value. `https://example.com/pasteloom-next-round2` was captured, found by search, and pasted back on the desktop.

## Image

PNG and TIFF pasteboard representations are accepted. ImageIO decodes at most 24 million pixels. The decoded pixels are rendered to sRGB RGBA, hashed with SHA-256, and saved as normalized PNG. This gives the same hash for visually identical PNG/TIFF representations. A repeated image copy remains a separate history event, while the asset file is shared. Images show an on-demand list thumbnail and a larger detail preview. Copy Back writes PNG and TIFF image representations.

## File

Finder file URLs are captured as references. Each reference stores the original file URL, name, extension, and content type identifier when macOS provides it. Availability is computed from the current file location; moved or deleted files show `Missing` without crashing. No original file bytes are copied. Source app is not stored because this MVP cannot determine it reliably from the pasteboard.

## Multi-file

All file URLs in one pasteboard event are stored as one history record with ordered child references. Finder copying two PNG files produced one `2 个文件` row. Copy Back writes all file URLs in the same order.

## Persistence

SQLite holds metadata and relative image paths. Image bytes live in `Application Support/com.gyryez.pasteloom.next/Assets/Images/<pixel-hash>.png`. A repository deletion removes an image asset after its last referencing row is deleted; file references never delete source files. The app reads its existing v1 database without losing text history. After restart, URL, image, and file records remained. Moving the original source PNG did not affect its stored thumbnail or large preview.

## Search

Text searches its content; URL searches its full value and domain; file records search names and extensions. Image content is not indexed. The UI keeps the search and history list separate from persistence and pasteboard access.

## Copy Back

The typed pasteboard integration test verified text, URL, PNG/TIFF image, and ordered file URLs. On the desktop, URL pasted into TextEdit with the full address, the stored image created a new image in Preview, and a copied file pasted into a Finder folder as a file. Own Copy Back writes are excluded from new capture.

## Performance Observation

Twenty distinct fixture images were copied through Preview and found as 20 distinct stored pixel hashes. Repeated copies of the same image shared one asset file. The history list remained responsive while scrolling through the image records; thumbnails are decoded on demand and held in a bounded `NSCache` (60 entries / 48 MB cost limit), rather than loaded as full images in the list. Observed app RSS was about 133 MB after the first 20 image events, 145 MB after scrolling, and about 140 MB after the additional distinct-image run. This is a short desktop observation, not a long-duration memory guarantee.

## Tests

`xcodebuild test` passed: 9 tests. They cover URL classification, classification priority, one logical multi-file capture, missing file safety, stable image hash and asset deduplication, v1 migration and integrity, typed Copy Back, search, persistence, and reload. Final Debug macOS build and tests passed with `CODE_SIGNING_ALLOWED=NO`.

## Desktop Validation

| Check | Result |
| --- | --- |
| Required URL copied, displayed with `example.com`, searched, and copied back | PASS |
| Preview image appeared with thumbnail and larger preview | PASS |
| Image persisted after restart and original source PNG was temporarily moved | PASS |
| Image Copy Back opened as an image in Preview | PASS |
| Finder file appeared with filename and availability | PASS |
| File Copy Back pasted as a file in Finder | PASS |
| Moved file displayed `Missing` without a crash; restored file displayed `Available` | PASS |
| Two Finder files became one logical history record | PASS |
| Three preexisting Round 1 text rows remained after migration and restart | PASS |
| SQLite `PRAGMA integrity_check` | PASS (`ok`) |
| Twenty distinct image assets persisted; list scrolled without a visible stall | PASS |

## Known Issues

- Capture polls `NSPasteboard.changeCount` every 0.6 seconds. Very fast clipboard changes between polls can be missed; this was observed once during the automated rapid Preview sequence and the missing fixture was captured on retry.
- Preview can place its temporary document file URLs on the pasteboard when selecting grouped image documents. Those events are correctly classified as file references and can later become `Missing`. They are separate clipboard changes from copying image pixels.
- Image input above 24 million pixels is skipped to bound decode memory. Image content search and source app detection are outside this round.
- File references are path based. Moving a source file makes its record unavailable until the file returns to that path.

## Old Source Accessed

NO

## Git

Commit: `feat: add URL image and file clipboard support` (the commit pointed to by the tag below)

Tag: `pasteloom-next-round2` (annotated)

No push.

## Ready For Round 3

YES — Round 2 scope is implemented and validated; the known limits above remain documented.
