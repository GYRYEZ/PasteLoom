# PasteLoom Next Screenshot Fix Report

## Root Cause

The existing normalizer already calculated a stable SHA-256 over dimensions and normalized pixels. One clipboard snapshot already selected one image representation. SQLite nevertheless inserted a new row for every image capture event, even when the fingerprint matched. During validation, two different PasteLoom Next builds were also running concurrently and writing to the same database; that condition produced identical rows from different processes. See `PASTELOOM_SCREENSHOT_DUPLICATE_FIX.md`.

## Fix

PNG → TIFF → NSImage fallback; one classified image per snapshot. Schema v3 indexes the existing `content_hash` fingerprint. A matching image updates the existing record's timestamp inside a SQLite write transaction; a different fingerprint inserts a new row. The policy has no time debounce. No old history is deleted.

## Screenshot Test

Ten spaced macOS screenshot shortcut attempts were made with only the new build running. New image rows observed: 4. New same-fingerprint duplicate groups: **0**. The shortcut interaction did not prove ten distinct clipboard updates, so a full 10/10 real screenshot pass is **NOT VERIFIED**.

## Rapid Different Screenshots

Expected: 2. Automated PNG image test at 100 ms: **2**. Two different desktop screenshot regions: **NOT VERIFIED**; the attempted UI shortcut sequence did not produce two observable new image records.

## App Name

Main Window: PasteLoom Next. Settings General: PasteLoom Next. About: PasteLoom Next. Menu Bar labels: PasteLoom Next. Quick Paste header: PasteLoom Next. App bundle: `PasteLoom Next.app`. `CFBundleDisplayName` and `CFBundleName`: PasteLoom Next.

## Bundle ID

`com.gyryez.pasteloom.next` (unchanged). Data directory and UserDefaults identity unchanged. Accessibility/TCC were not modified.

## Tests

Passed: 22. Failed: 0. Includes all existing tests and new representation, deduplication, rapid-distinct-image and migration tests.

## SQLite Integrity

PASS: `PRAGMA quick_check = ok`; schema user_version 3.

## Acceptance Build

`AcceptanceBuild/PasteLoom Next.app`（该目录为本地忽略的验收产物，不随源码发布）

`AcceptanceBuild/` is ignored by `.gitignore`.

## Git

Commit: this report is included in `fix: deduplicate screenshot captures and rename app to PasteLoom Next`.
No new release tag. No push.

## Old Source Accessed

NO
