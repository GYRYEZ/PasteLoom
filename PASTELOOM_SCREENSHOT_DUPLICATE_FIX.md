# Screenshot duplicate diagnosis and fix

## Capture pipeline before the change

`ClipboardService` checks `NSPasteboard.changeCount` every 0.20 seconds and reads one snapshot only after a change. `SystemContentPasteboard` chooses PNG before TIFF; `ClipboardClassifier` chooses files, then one image, then URL, then text. One snapshot therefore already produced at most one image input. The image normalizer renders source data into a bounded, 8-bit sRGB RGBA bitmap and hashes width, height and normalized pixel bytes with SHA-256. The hash was already stable across the PNG and TIFF test representations.

The defect was in persistence: each image capture event created a new `history_items` row even when `content_hash` matched an existing image row. The same hash only reused the asset file. A screenshot application writing identical image content on successive pasteboard change counts therefore produced duplicate history rows. The polling code has no way to know whether two change counts represent one user screenshot, so the fix uses the normalized content fingerprint. This is not a time-only debounce.

During desktop validation, an older AcceptanceBuild and the new test build were also found running simultaneously. Both monitored the same general pasteboard and wrote to the same SQLite database. Two rows with an identical hash were observed roughly 40 ms apart while both processes ran. The older binary could still insert duplicates even after the new binary was fixed. That older process was closed before the isolated test. This is a separate testing/installation condition; production acceptance should run one PasteLoom Next process.

## Fix and duplicate policy

- The pasteboard adapter reads one image representation: PNG, TIFF, or NSImage TIFF fallback. Files retain higher classification priority.
- The existing `content_hash` is the image content fingerprint. It is SHA-256 of dimensions and normalized sRGB bitmap bytes; encoded PNG bytes and metadata are not hashed.
- SQLite schema v3 adds an index for image fingerprint lookup. The migration is transactional and preserves v1/v2 history. Existing image rows keep their fingerprints; old duplicate rows are intentionally not deleted.
- Before inserting a normalized image, the repository looks for an existing image with the same fingerprint inside its write transaction. It updates that record's `captured_at` to the later timestamp and returns. No time threshold is used. Recopying the same image much later promotes one existing record; copying a different image even 100 ms later inserts a distinct row.
- Fingerprints are calculated only on changed image payloads, not during idle polling. Existing assets are not decoded for duplicate lookup.
- The existing Copy Back self-write suppression remains unchanged.

## Validation

Automated tests cover PNG/TIFF equal fingerprints and one logical snapshot, two image change counts resulting in one stored item, different images 100 ms apart resulting in two items, re-copying the same image much later without row growth, Copy Back suppression, and v1/v2 migration. All 22 tests passed.

In an isolated single-process desktop session, ten spaced macOS screenshot shortcut attempts yielded four new image rows; no newly observed fingerprint had more than one row. Identical full-screen pixels may be intentionally merged, and the shortcut tool did not expose enough evidence to verify that all ten attempts became separate pasteboard changes. A separate two-region shortcut attempt did not yield two observable new records. **Ten-of-ten real screenshot delivery and the two-region desktop case remain unverified.**

No pre-existing duplicate records were removed from the user's history. SQLite `quick_check` returned `ok`, and the live database migrated to user_version 3.
