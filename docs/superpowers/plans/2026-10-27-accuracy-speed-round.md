# Accuracy round with speed held: weak-grid rescue (2026-10-27)

Tree: `4d13d6c` (bench6 accuracy bench in place). Benches: bench5 = speed,
bench6 = accuracy (65 truth classes, 8 photos).

## Problem (measured, both benches agree)

`r4_notice_mixed` scores 0/6 end-to-end. The grid scan locks onto one stray
notice line ("Claim at the office." -> Fri 21:00-21:30) and returns a 1-row
result. The screen then trusts the grid blindly (pre-O1 rationale: the text
cascade's result was discarded anyway) and never runs the flat-text cascade
that would parse the 6 real classes. The grid result is *weak* —
`GridScanStats.readCleanText` is false (too few alnum chars) — but nothing
checks that after the O1 skip was introduced.

## Fix: rescue the weak grid with the text cascade, chosen by score

1. `ScheduleOcrService.scanGridImage` gains an optional out-param
   `GridScanStats? stats` (same pattern O3 added to `TimetableGridScanner.scan`),
   carrying the FIRST upright scan's stats. Backward compatible.
2. `ParseChain.scoreRows(rows, {meanConfidence})`: the row-level mirror of
   `ParseChain.score` (rows*100 + distinct subjects*8 + distinct slots*4 +
   meanConfidence*12) so grid candidates and text candidates can compete on
   one scale.
3. Import screen: a grid result is *suspicious* when it has <= 2 rows AND the
   upright scan did not read clean text (real timetable grids read 40+ alnum
   chars at >= .6 confidence; notice/chat look-alikes lock onto 1-2 stray
   lines). For suspicious grids the text cascade ALSO runs and the candidate
   with the higher ParseChain score wins; empty text candidates never win.
   Clean or row-rich grids keep the O1 skip — no extra passes, speed intact.
4. PDFs unchanged (their text is already extracted and the path carries a
   review warning).
5. bench5 + bench6 mirrors updated to the same policy; new screen-level test
   `import_weak_grid_rescue_test.dart` pins the rescue (bogus 1-row grid vs
   parseable text -> text wins) and the keep-grid case (clean stats -> no
   text stage).

## Expected cost / win

- Speed: ONLY suspicious weak grids pay for the text cascade (+4-6 recognize
  calls on bench5 = one fixture, r4_notice_mixed). The other 10 fixtures keep
  identical call counts. On-device: weak-grid photos pay a few seconds; real
  timetables pay nothing.
- Accuracy: r4_notice_mixed 0/6 -> 6/6 expected; bench6 micro F1 0.944 -> ~1.0
  if no other fixture regresses (score gate protects the 7 perfect ones).

## Verification

bench6 after-run (accuracy), bench5 after-run (speed), full suite, analyze,
format; before/after tables appended to this doc.

## Results (2026-10-27, commit to follow)

First gate attempt (suspicious = few rows AND not readCleanText) did NOT
fire: the probe showed every bench4 photo reads plenty of clean text
(lines 34-115, alnum 155-471, conf .87-.96) - text quality cannot tell a
locked grid from a real one. The gate that works is STRUCTURAL: how many
lines the scan read vs how many rows the geometry mapped.

    suspicious = rows in 1..2 && stats.lineCount > rows * 8

(real grids land most lines in cells; notice_mixed read 73 lines and mapped 1)

| metric | before rescue (4d13d6c) | after rescue | delta |
|---|---|---|---|
| bench6 recall (65 classes) | 0.908 | **0.985** | +0.077 |
| bench6 precision | 0.983 | 0.985 | +0.002 |
| bench6 F1 | 0.944 | **0.985** | +0.041 |
| r4_notice_mixed | 0/6 matched, 1 FP | 5/6 matched, 1 FP | +5 classes |
| bench5 recognize calls | 99 | 100 | +1 |
| bench5 wall seconds | 98.0 | 99.9 | +1.9 |
| vs pre-optimization d508f6b | 198 calls / 238.8s | 100 calls / 99.9s | 2.39x faster |

All other 10 fixtures keep identical call counts and identical parsed rows.
Evidence: download/bench6_accuracy_rescued.json, download/bench5_rescued.json
(bench5's per-fixture `rescued_from_grid` flag fires only on r4_notice_mixed).
Full suite: 367 pass / 12 skip / 0 fail (delta vs 365: +2 = the rescue screen
tests). The one remaining miss on notice_mixed is a time-off row (class found,
one time boundary imperfect) - engine-level, left for a future round.
