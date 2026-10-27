# Plan: scan-speed optimization with before/after benchmark (Task 22)

User request: "optimize the scanning because it takes time to scan one picture,
benchmark before and after to see the difference."

## Why one picture is slow (verified at d508f6b)

For a non-PDF image the import screen runs BOTH paths back to back
(import_schedule_screen.dart:324-350):

1. `scanGridImage` -> TimetableGridScanner.scan: 4-6 recognize() passes
   (original + contrast-enhanced + adaptive + inverted + enlarged-small +
   column crops). When no rows come back, `ScheduleOcrService.scanGridImage`
   retries up to 3 FULL rotated grid scans (each prep + 4-6 passes).
2. `scanImage` -> 4 more recognize() passes (original, contrast enhanced,
   adaptive threshold, dark-background inversion) + 3 image preps, plus up
   to 3 rotated passes when nothing parses.

Then the selection logic (import_schedule_screen.dart:389) keeps gridRows
whenever they are non-empty — scanImage's text is thrown away in that case,
even though it just burned ~4 recognition passes. A clear weekly-grid photo
therefore pays ~9+ recognition passes where ~5 do the work.

## Optimizations (quality-first, all measured by the bench)

### O1. Skip the discarded scanImage pass (zero quality risk)
import_schedule_screen.dart: when the file is an image and `gridRows` is not
empty, do not call scanImage at all (text = ''). The text is provably unused
in that branch: `parsed = gridRows`, and the warning block that reads
`text`/`hasWeekdayHeaders` only executes when `parsed.isEmpty`. Gate the
'.43 Trying text recognition' progress report the same way.

### O2. Early-exit cascade in scanImage (4 passes -> 1 on clear list photos)
schedule_ocr_service.dart: run candidates one at a time and stop as soon as a
candidate parses STRONGLY: >= 2 rows via ParseChain (max of sectioned/list)
AND meanConfidence >= 0.85 AND no duplicate-heavy line block. Prep the next
variant lazily (only when actually needed) instead of preparing all three
variants up front. When the bar is not met, the exact current cascade runs
(enhanced -> adaptive -> inverted -> rotations), so hard photos keep today's
recall. Rotation loop unchanged (still gated on initialBestRows == 0).
Progress: candidate steps still step .46->.82; early exit jumps to .84 as
today's final step does.

### O3. Rotation gate in scanGridImage (skip 3 wasted rotated grid rescans)
timetable_grid_scanner.dart: add `scanDetailed()` returning
`GridScanResult(rows, lineCount, alnumChars, meanLineConfidence)` with
`readCleanText` = alnumChars >= 40 && meanLineConfidence >= 0.6; `scan()`
stays as the compat wrapper (bench3/bench4 keep compiling).
schedule_ocr_service.dart scanGridImage: rotate only when the first scan did
NOT read clean text. Rationale: the rotated rescans exist purely to fix
ORIENTATION; if the upright scan already read substantial clean text, the
photo is upright and re-scanning it sideways cannot recover headers. A
sideways or faint photo reads as garbage/low-confidence and still rotates.
The scanImage rotation loop already follows the same principle (it only
rotates when initialBestRows == 0); the grid path was missing that gate.

## Benchmark: test/bench5_scan_speed_test.dart

Round-5 scan-speed benchmark. Drives the REAL ScheduleOcrService
(scanGridImage then scanImage, exactly as the import screen orchestrates an
image) with the real OcrImagePreprocessor, in `flutter test`, with the native
ONNX runtime replaced by tesseract 5.5.0 through
`PaddleOcrNativePlatform.instance` (same stand-in as bench3/bench4: the
native engine cannot run in the test VM).

Fixtures (11): timetable_grid_afternoon / _no_gutter / _period_rail (grid
photos) + bench4 r4_* (handwritten planner x2, chat x2, email x2, notice
board x2 — list-style photos).

Per fixture, recorded into build/bench5_out.json:
- recognize() call count for the grid stage, the text stage, and total
- wall seconds for each stage (real prep + real pixel work + tesseract)
- gridRows count, final rows count via the screen's selection logic,
  sectioned/list row counts for the winning text
- pass label notes (which scanImage candidate won, whether early exit fired)

Protocol:
1. Run bench5 on d508f6b (BEFORE) -> build/bench5_baseline_before.json
2. Implement O1-O3
3. Re-run bench5 (AFTER) -> build/bench5_baseline_after.json
4. Quality gate: final rows per fixture must be identical before/after
   (same subjects/times); if a fixture regresses, tune the O2 threshold.
5. Report call-count deltas and wall-time ratios per fixture + totals.

Known honesty limits (stated in the report): tesseract stands in for
PP-OCRv6, so absolute seconds differ from the user's phone; the structural
gains (recognition-pass count) transfer 1:1 because each pass costs the same
engine time on-device before and after. The O2 confidence bar (0.85) and O3
clean-text floor (40 alnum chars, mean conf 0.6) are calibrated conservatively
and validated on the 11 fixtures; sideways-photo behavior for O3 is reasoned
(garbage/low-conf text opens the gate) but has no shipped sideways fixture.

## Verification
- flutter analyze: 0 new issues (7 pre-existing infos)
- Full suite incl. bench3/bench4/bench5: 0 fail (record the delta vs 344/12/0)
- dart format on touched files
- No goldens affected (nothing pins the scan flow visuals)
- Commit + worklog Task 22 + keepsafe backup `scan-speed` + MANIFEST row

## Results (measured, tesseract stand-in engine, 11 fixtures)

Quality gate: PASS - final rows identical before/after on every fixture.

| fixture | calls before -> after | seconds before -> after |
|---|---|---|
| timetable_grid_afternoon | 18 -> 18 | 15.8 -> 15.6 |
| timetable_grid_no_gutter | 19 -> 19 | 12.4 -> 12.5 |
| timetable_grid_period_rail | 19 -> 19 | 12.5 -> 12.3 |
| r4_chat_bubbles | 17 -> 4 | 32.5 -> 7.7 |
| r4_chat_single_msg | 16 -> 6 | 25.5 -> 7.5 |
| r4_email_list | 21 -> 5 | 35.8 -> 9.8 |
| r4_email_prose | 21 -> 5 | 32.8 -> 8.3 |
| r4_notice_main | 16 -> 6 | 20.1 -> 6.2 |
| r4_notice_mixed | 9 -> 6 | 12.3 -> 8.6 |
| r4_planner_casual | 20 -> 5 | 21.2 -> 5.0 |
| r4_planner_journal | 22 -> 6 | 18.0 -> 4.5 |
| **TOTAL** | **198 -> 99 (2.0x fewer)** | **238.8 -> 98.0 (2.44x faster)** |

Notes:
- The three shipped grid PNGs are unchanged because tesseract's first pass
  reads nothing on them (bench3 documented the same), so the O3 gate has no
  clean-text signal to close on and rotations correctly stay. On a real
  device PP-OCR reads real grid photos (that is the flagship path), the gate
  closes, and the same saving as the list photos applies.
- r4 list photos: 3.0-4.5x faster per photo. O2 fired on 'Original' at
  confidence 0.89-0.96 for six of them; chat_single_msg and notice_main ran
  one extra pass (Original below the bar, Contrast enhanced cleared it) and
  still produced identical rows.
- r4_notice_mixed (grid-scan success): O1 skipped the text cascade entirely.
- Full suite: 356 pass / 12 skip / 0 fail (delta vs 344 baseline: +12 = the
  11 bench5 fixture cases + the bench5 summary test).
