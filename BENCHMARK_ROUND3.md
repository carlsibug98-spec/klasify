# Klasify OCR importer — Round 3 benchmark (new schedule types)

Date: 2026-10-24 · Tree: v49 (+ one pipeline fix, see below) · Engine proxy: tesseract 5

## Why round 3

Rounds 1–2 covered 26 styles (`ocr_timetables_all` 14 + `ocr_timetables_hard` 12).
The user asked to test **other photos so we can see if the importer misses other
types of schedules**. Round 3 renders 12 types that neither round covered, with
exact ground truth baked in at render time (207 truth classes total):

`sat_column` (Mon–Sat) · `merged_cells` (subjects spanning 2 slots) ·
`vertical_headers` (rotated day names) · `am_pm_noon` (12h + noon wrap) ·
`dot_times` (Indonesian 07.00–08.30 + Sen/Sel/Rab/Kam/Jum) · `pastel_blocks`
(white text on colored blocks) · `two_line_wrap` (long subjects wrapped in cell) ·
`no_time_column` (P1..P6 only) · `portal_screenshot` (web portal chrome) ·
`alternating_slot` (Math / PE weekly alternation) · `phone_screenshot`
(1080×2200 app UI) · `spreadsheet` (Excel chrome).

## Method

The real import pipeline runs inside `flutter test`
(`test/bench3_round_test.dart`): pixel grid analysis, cell assignment and
parsers are the shipped code. The on-device PP-OCRv6 ONNX engine cannot run in
the test VM, so tesseract (psm 11, word-gap split into per-cell line boxes)
stands in. Tiers:

- **t1** — ground-truth lines → `TimetableParser` (parser ceiling)
- **t2a / t2b** — tesseract flat text (cell-split / row-joined) → parser (flat fallback path)
- **t3** — tesseract boxes → `TimetableGridScanner` (full grid path)

**Caveat:** absolute numbers measure "pipeline + tesseract". The app's real
engine (PP-OCRv6 det+rec) is stronger on rotation, low light and contrast, so
hard-set t3 numbers below are a lower bound. Layout-level findings are
engine-independent.

## Bug found and fixed in this round

`timetable_grid_scanner.dart` passed `maxGap: h * .12` (strict `<`) to
`inferTimetableRowSpacing`. Any timetable whose row spacing is ≥ 12% of the
image height (tall grids — e.g. 120px rows on a 1000px photo) got
`rowSpacing = null` and the scanner **silently returned zero rows**. That one
boundary killed 10 of 12 round-3 photos and explains "nothing imports" reports
for tall clear photos. Fixed to `h * .2` (still rejects missing-label double
gaps). Full suite: 276/276 green, analyzer clean.

## Round-3 results (after the fix)

# Klasify OCR importer - Round 3 benchmark (new schedule types)

Engine proxy: tesseract (psm 11, word-gap split) stands in for the
on-device PP-OCRv6 engine. Tiers: t1 = ground-truth lines -> parser,
t2a = tesseract cell-split flat text -> parser, t3 = tesseract boxes -> full grid
scanner (real pixel analysis + cell assignment).

| Photo | style | n | tier | full | time-off | day-off | missed | FP |
|---|---|---|---|---|---|---|---|---|
| r3_sat_column.png | sat_column | 24 | t2a | 0 | 0 | 0 | 24 | 0 |
| r3_sat_column.png | sat_column | 24 | t2b | 0 | 0 | 0 | 24 | 0 |
| r3_sat_column.png | sat_column | 24 | t3 | 18 | 0 | 2 | 4 | 3 |
| r3_merged_cells.png | merged_cells | 23 | t2a | 0 | 0 | 0 | 23 | 0 |
| r3_merged_cells.png | merged_cells | 23 | t2b | 0 | 0 | 0 | 23 | 0 |
| r3_merged_cells.png | merged_cells | 23 | t3 | 16 | 4 | 0 | 3 | 2 |
| r3_vertical_headers.png | vertical_headers | 15 | t2a | 0 | 0 | 0 | 15 | 0 |
| r3_vertical_headers.png | vertical_headers | 15 | t2b | 0 | 0 | 0 | 15 | 0 |
| r3_vertical_headers.png | vertical_headers | 15 | t3 | 4 | 0 | 0 | 11 | 9 |
| r3_am_pm_noon.png | am_pm_noon | 12 | t1 | 12 | 0 | 0 | 0 | 0 |
| r3_am_pm_noon.png | am_pm_noon | 12 | t2a | 0 | 0 | 0 | 12 | 0 |
| r3_am_pm_noon.png | am_pm_noon | 12 | t2b | 2 | 1 | 0 | 9 | 0 |
| r3_am_pm_noon.png | am_pm_noon | 12 | t3 | 0 | 0 | 0 | 12 | 0 |
| r3_dot_times.png | dot_times | 19 | t2a | 0 | 0 | 0 | 19 | 0 |
| r3_dot_times.png | dot_times | 19 | t2b | 0 | 0 | 0 | 19 | 0 |
| r3_dot_times.png | dot_times | 19 | t3 | 0 | 0 | 0 | 19 | 0 |
| r3_pastel_blocks.png | pastel_blocks | 16 | t2a | 0 | 0 | 0 | 16 | 0 |
| r3_pastel_blocks.png | pastel_blocks | 16 | t2b | 0 | 0 | 0 | 16 | 0 |
| r3_pastel_blocks.png | pastel_blocks | 16 | t3 | 0 | 0 | 0 | 16 | 0 |
| r3_two_line_wrap.png | two_line_wrap | 14 | t2a | 0 | 0 | 0 | 14 | 0 |
| r3_two_line_wrap.png | two_line_wrap | 14 | t2b | 0 | 0 | 0 | 14 | 0 |
| r3_two_line_wrap.png | two_line_wrap | 14 | t3 | 10 | 3 | 0 | 1 | 0 |
| r3_no_time_column.png | no_time_column | 20 | t2a | 0 | 0 | 0 | 20 | 0 |
| r3_no_time_column.png | no_time_column | 20 | t2b | 0 | 0 | 0 | 20 | 0 |
| r3_no_time_column.png | no_time_column | 20 | t3 | 0 | 0 | 0 | 20 | 0 |
| r3_portal_screenshot.png | portal_screenshot | 22 | t2a | 0 | 0 | 0 | 22 | 1 |
| r3_portal_screenshot.png | portal_screenshot | 22 | t2b | 0 | 0 | 0 | 22 | 0 |
| r3_portal_screenshot.png | portal_screenshot | 22 | t3 | 20 | 0 | 1 | 1 | 1 |
| r3_alternating_slot.png | alternating_slot | 14 | t2a | 0 | 0 | 0 | 14 | 0 |
| r3_alternating_slot.png | alternating_slot | 14 | t2b | 0 | 0 | 0 | 14 | 0 |
| r3_alternating_slot.png | alternating_slot | 14 | t3 | 9 | 1 | 3 | 1 | 0 |
| r3_phone_screenshot.png | phone_screenshot | 12 | t1 | 12 | 0 | 0 | 0 | 0 |
| r3_phone_screenshot.png | phone_screenshot | 12 | t2a | 0 | 0 | 0 | 12 | 0 |
| r3_phone_screenshot.png | phone_screenshot | 12 | t2b | 2 | 0 | 7 | 3 | 0 |
| r3_phone_screenshot.png | phone_screenshot | 12 | t3 | 0 | 0 | 0 | 12 | 0 |
| r3_spreadsheet.png | spreadsheet | 16 | t2a | 0 | 0 | 0 | 16 | 0 |
| r3_spreadsheet.png | spreadsheet | 16 | t2b | 0 | 0 | 0 | 16 | 0 |
| r3_spreadsheet.png | spreadsheet | 16 | t3 | 11 | 0 | 1 | 4 | 2 |


Hard-set cross-check (12 real photos, 184 classes; t3 = tesseract proxy lower
bound): full-match rate t1 12.5% (grid-style flat text cannot encode columns —
expected), t3 1.1%. List-like styles on t1: ph_college 10/12, receipt 7/8,
whiteboard 5/10, day_sections partial — see gaps below.

## Failure taxonomy by schedule type

1. **Tall grids silently imported nothing** — FIXED (maxGap boundary above).
2. **No left time gutter → total bail** (`pastel_blocks` 0/16, any aesthetic
   schedule with times inside cells): the scanner only reads clock ticks from a
   left gutter; with none, `ticks.isEmpty` → `[]`. Needs per-cell time parsing.
3. **Period-only rails (P1..P6) unsupported in the photo path**
   (`no_time_column` 0/20): PDF path got period rails in v34; photo path still
   bails on missing clock ticks. Nominal-grid synthesis + .74 flag exists in
   `TimetableParser` but never runs here.
4. **Non-English day headers** (`dot_times` 0/19): Sen/Sel/Rab/Kam/Jum are read
   by OCR but don't match the weekday map → no columns. Dictionary fix (id/ms +
   common locales) is small, free and offline.
5. **Vertical/rotated day headers** (`vertical_headers` 4/15 + 9 FP): columns
   mis-assigned, phantom rows. PP-OCR may read rotated headers better than
   tesseract; needs on-device confirmation plus a rotated-header path.
6. **Multi-class lines** (whiteboard 5/10): "MON - Algebra 8AM-9AM / Science
   10AM-11AM" — only the first time range is parsed; the second class is lost
   or merged. Parser takes `timePattern.firstMatch` only.
7. **Merged cells** (16/23 full, 4 time-off): spans work but slot-snap rounds
   2-row spans to one row when OCR text sits high in the cell.
8. **List-style photos** (`am_pm_noon`, `phone_screenshot`): grid scanner
   bails by design; parser ceiling is 12/12 on both with clean lines — real
   accuracy depends on PP-OCR det line grouping (tesseract proxy garbles
   sparse lists, so t2b 2/12 is a proxy artifact, not a parser gap).
9. **Contrast limits** (`pastel_blocks` OCR layer): white-on-color text — the
   whole-image invert only triggers when the global median is dark; per-region
   inversion may be needed (on-device check first).

## Updated backlog (priority order, all free + offline)

1. ✅ maxGap boundary fix (this round, shipped in v50).
2. Period rails for the photo path (reuse `PeriodTimes` nominal grid; flag .74).
3. Per-cell clock parsing when no left gutter exists (times inside blocks).
4. Weekday dictionary: Indonesian `sen sel rab kam jum`, Filipino, Spanish.
5. Multi-class line parsing (split on '/' between time-range pairs).
6. Vertical header support (rotate header band 90° before matching).
7. On-device A/B: rerun round 3 + hard set on the real PP-OCRv6 engine via the
   dev importer screen; only then consider preprocessing changes (per-region
   inversion).

## Reproduce

```bash
flutter test test/bench3_round_test.dart      # writes build/bench3_out.json
python3 ../scripts/bench3_generate_photos.py  # regenerates fixtures + truth
python3 ../scripts/bench3_ocr_fixtures.py     # tesseract fixtures
python3 ../scripts/bench3_score.py            # build/bench3_table.md
```

