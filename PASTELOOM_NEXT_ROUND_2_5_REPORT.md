# PasteLoom Next Round 2.5 — Clipboard Capture Reliability

## Baseline monitor analysis (before changes)

- **Polling interval:** `0.6` seconds.
- **Timer and task:** `Timer.scheduledTimer` is created on the main run loop in its default mode. Every firing queues a `Task { @MainActor in self?.poll() }`, even when the clipboard is idle. This adds an unnecessary task hop and can delay a check while the main actor is busy.
- **Work per poll:** `poll()` reads `pasteboard.changeCount` and compares it with `lastChangeCount`. An unchanged count returns immediately. For a changed count, it reads a `ClipboardSnapshot`, checks that the count stayed stable during the read, classifies one current payload, and calls `onCapture`.
- **Idle payload reads:** No. `readSnapshot()` is called only after a changed `changeCount`. It may then read file URLs, PNG/TIFF data, URL and text representations. Image normalization and database insertion happen later in `AppModel`.
- **Lifecycle:** `ClipboardService` is constructed by `AppModel`. Capture starts at app launch if storage is available and the persisted capture setting is enabled. Pause stops and invalidates the timer; resume starts a new timer and takes the current `changeCount` as its baseline. Copy Back writes to the pasteboard and updates that baseline to suppress self-capture.
- **Inactive/background:** The app does not intentionally stop capture when inactive. The main run loop timer should continue while the process is scheduled, but default run-loop mode can defer firings during event tracking. Sleep, suspension, and main-thread stalls can also delay observation. `NSPasteboard` exposes only the latest state; overwritten intermediate payloads cannot be recovered by polling.

## Interval evaluation

An isolated macOS benchmark used a named `NSPasteboard` and a main-run-loop timer. Each candidate ran for six idle seconds; the callback only read `changeCount` and would read payload only if it changed. Results:

| Interval | Timer checks | Payload reads | Process CPU during 6 s | Approx. CPU share |
| --- | ---: | ---: | ---: | ---: |
| 0.10 s | 60 | 0 | 0.00361 s | 0.060% |
| 0.20 s | 30 | 0 | 0.00174 s | 0.029% |
| 0.25 s | 24 | 0 | 0.00136 s | 0.023% |

The measured idle cost is low for all three. `0.20` s was selected as a smaller overwrite window than `0.25` s while still using only five lightweight checks per second. The timer now runs in main-run-loop common modes, with `0.02` s tolerance, and calls `poll()` directly on the main actor. Unchanged counts never read a clipboard payload. No new queue, cache, or recovery mechanism was added.

The service also tracks `missedChangeCountDelta` for diagnostics. It counts `changeCount` increments that occurred between observations; it does **not** represent recoverable historical items, and no missing item is fabricated. Copy Back resets the observed count to the final count of the app's own write.

## Burst and regression tests

All 14 `xcodebuild test` cases passed (five new tests plus the nine Round 2 tests). New deterministic tests verify idle polls perform zero snapshot reads, a three-write burst yields only the latest item and records a delta of two, text/URL/image/single-file/multi-file events remain typed and one-per-event, all Copy Back types suppress self-capture, and a pasteboard change during snapshot reading retries on the next poll without saving the stale payload. The tests use an original in-memory fake pasteboard and do not depend on the old project.

## Desktop observation

The updated Debug app was launched with the existing Round 2 database. Three separate TextEdit plain-text copies made in 2.4 seconds produced exactly three text records, in order. A URL copied from TextEdit was stored as `url`; an image copied from Preview was stored as `image`; Finder single-file and two-file copies were stored as one `file` record per event. Copy Back of one text record did not add a duplicate. The app remained responsive in the background during copies.

With the app idle, a ten-second process observation showed CPU time changing from `0:03.37` to `0:03.38` and RSS staying at about `154 MB`. This is a short local observation, not a long-running energy benchmark.

## External burst validation

An independent Python harness launched the system `pbcopy` command once per item. It wrote exactly `PL_BURST_001` through `PL_BURST_020` to the general pasteboard for each interval, paced by `time.monotonic()`. The harness did not call PasteLoom Next or its Copy Back API. Before each run it recorded a wall-clock baseline; after the last write it allowed 0.8 seconds for capture and queried new SQLite rows by `captured_at`. Runs were separated by another 0.7 seconds. It checked type, item count, duplicate labels, missing labels, and order. Actual write spacing remained close to the requested intervals (about 483–517, 294–305, 242–255, 190–211, and 95–107 ms respectively).

| Interval | Attempted | Captured | Missed |
|---|---:|---:|---:|
| 500 ms | 20 | 20 | 0 |
| 300 ms | 20 | 20 | 0 |
| 250 ms | 20 | 20 | 0 |
| 200 ms | 20 | 20 | 0 |
| 100 ms | 20 | 10 | 10 |

Every captured row had type `text`. No run had duplicate records or order inversions. The 100 ms run captured even-numbered items and missed odd-numbered items. This is expected when writes outpace the 200 ms poll; it is an observation of this run, not a guarantee for other timing phases. `NSPasteboard` exposes only the current state. Once a later external write overwrites an intermediate state before PasteLoom Next observes it, that intermediate content cannot be reliably recovered. The monitor did not fabricate replacement records or save the latest item multiple times.

After the burst run, the UI remained responsive to search and scroll. The app's RSS was about `173 MB`. An idle ten-second CPU observation changed process CPU time from `0:56.35` to `0:56.37`, with `0.0%` CPU at the final sample. SQLite `PRAGMA quick_check` returned `ok`. The complete original 14-test suite was rerun and passed (14 passed, 0 failed).

## Known limits

Polling cannot recover clipboard contents overwritten before the next read, even if `changeCount` indicates multiple changes. Heavy main-thread work, process suspension, system sleep, or an external app's unusually rapid writes can still cause gaps. The `missedChangeCountDelta` metric reflects counter transitions only; one external write may itself cause multiple transitions. No payload is decoded or database query made during an idle poll.

## Git

Baseline: `7168318` (`pasteloom-next-round2`). This round changes the monitor, its tests, and this report only. Commit message: `fix: improve clipboard capture reliability`. No old Clipth or PasteLoom source was accessed. No push.

The burst validation found no business-code bug requiring a source change. Its results are recorded in a separate documentation commit; the final Round 2.5 annotated tag points to that commit.
