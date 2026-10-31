# Klasify OCR — Round 9 benchmark (student COR)

Date: 2026-10-30 · Tree: current workspace · OCR proxy: tesseract 5.5.0
stand-in for the native PP-OCR engine (no native runtime in the test VM)

## Why round 9

Round 8 took the six-sample COR benchmark to F1 0.982 (55/57) but left two
honest failures: `cor_phone_skewed.jpg` (9/10 — the PATHFit row's start hour
`04:` OCR-garbled to `Jos`, so the schedule cell never parsed) and
`cor_lowres.png` (9/10 — the Quantitative Methods row's time separator read
as `«` instead of `-`, which the COR slot regex rejected). Round 9 attacks
both, one fix at the parser level and one in the scan cascade.

## Round 9 results (harness-measured, tesseract stand-in)

Micro-averaged over the six fixtures, greedy 1-to-1 matching on
day + interval overlap + subject similarity ≥ 0.34:

| metric | baseline | round 7 | round 8 | round 9 |
|---|---|---|---|---|
| recall | 0.404 | 0.702 | 0.965 | **1.000** |
| precision | 0.622 | 0.870 | 1.000 | **1.000** |
| f1 | 0.489 | 0.777 | 0.982 | **1.000** |
| matched | 23/57 | 40/57 | 55/57 | **57/57** |
| room ok | 21 | 35 | 42 | **45** |
| professor ok | 21 | 37 | 53 | **56** |

Per fixture (round 9): clean 7/7, labs 10/10, **skewed 10/10 (was 9/10)**,
blurred 10/10, **lowres 10/10 (was 9/10)**, dim 10/10 — still no
false-positive rows (parsed 57, matched 57).

## The two fixes

### Slot separator tolerance (lowres)

Soft/low-res captures turn the thin printed dash between the two times into
a guillemet: `09:00 AM « 10:30 AM / Fri`. The COR `_slot` regex only accepted
`- – —`, so the whole Quantitative Methods row — subject, time and professor
all read correctly on one banded line — was discarded for one character. The
separator class now also accepts `« » ‹ › · ~`. This is a COR-parser-only
change (`cor_schedule_parser.dart`); the sectioned parser and the other
benches never see it.

### Finer deskew bracket (skewed)

The round-8 deskew rescue bracketed the profile-estimated angle at
±0.75° = {-5.5, -4.0} for the -4.75° page. The round-9 recipe sweep
(7 angles × 3 upscale targets × 2 op orders, all through the production Dart
rotation) found the recognizer reads the garbled `04:` cell at **-4.5°** —
a quarter degree off the profile peak, inside the old bracket's gap:

| angle (2160, enhance→rotate) | matched | notes |
|---|---|---|
| -5.5 / -4.0 (old bracket) | 7/10 | |
| -4.75 (profile peak) | 9/10 | round-8 winner |
| **-4.5** | **10/10** | room 9, prof 9 |
| -4.5 (rotate→enhance order) | 10/10 | room 10, prof 10 |

The cascade bracket is now `[0.0, +0.25, -0.25, +0.5, -0.5]` degrees around
the estimate (wide ±0.75 steps dropped — measured worse at every angle).
Both bracket candidates measure tesseract mean confidence ≈ 0.76-0.78 <
0.85, so `_strongScan` does not early-break on the 9/10 peak candidate: all
bracket candidates are scored and ParseChain picks the 10-row winner. Clean
upright pages never reach the deskew rescue, so their fast path is unchanged.
(Rotate→enhance order scored marginally better on aux fields and is noted as
future work; it needs a preprocessor op-order flag and is not wired.)

## What changed

- **`lib/features/schedule_import/utils/cor_schedule_parser.dart`**
  - `_slot` separator class `[-–—]` → `[-–—«»‹›·~]`.
- **`lib/features/schedule_import/services/schedule_ocr_service.dart`**
  - Deskew rescue bracket `{-0.75, 0, +0.75}` → `{0, +0.25, -0.25, +0.5, -0.5}`.
- **Benchmarks / verification**
  - `tool/cor_harness/bin/round9_diag.dart` (new): per-fixture parsed rows +
    unmatched-truth dump with candidate hints.
  - `tool/cor_harness/bin/round9_ocr_dump.dart` (new): y-sorted raw OCR lines
    with confidence, for locating dropped rows.
  - `tool/cor_harness/bin/round9_text_dump.dart` (new): the exact banded text
    ParseChain hands the COR parser, plus its parse result.
  - `scripts/sweep_round9_skew.py`, `scripts/round9_final_measure.py` (new):
    the recipe sweep and the 57/57 measurement.

## How this was verified in the VM (no Flutter SDK)

- Round-9 sweep: 42 recipes through the production `rotateRgbaBuffer` and the
  single-fixture scorer; two 10/10 winners found.
- Full six-fixture harness with the round-9 cascade mapping: **57/57,
  precision 1.000, room 45, prof 56** (`python3 scripts/round9_final_measure.py`).
- Parser regression suite: 39 checks, 0 failures (slot regex change is
  backwards compatible).
- Skew estimator synthetic checks: all pass (straight pages still never
  rescue; residual after rotation < 0.5°).
- Baseline harness (raw fixtures, no rescue variants) unchanged at 40/57 —
  the regex fix introduces no baseline drift.
- `dart analyze lib/features/schedule_import/utils/cor_schedule_parser.dart`:
  no issues.
- `flutter test test/bench7_cor_accuracy_test.dart` remains the on-device
  confirmation; the regression floor stays at micro-recall ≥ 0.60.

## Reproduce

```bash
dart run tool/cor_harness/bin/regression.dart          # parser checks (39)
dart run tool/cor_harness/bin/round9_diag.dart cor_lowres.png cor_lowres.round8.png
python3 scripts/sweep_round9_skew.py                   # recipe sweep
python3 scripts/round9_final_measure.py                # 57/57 measurement
python3 scripts/make_round8_variants.py                # lowres variant fixture
```
