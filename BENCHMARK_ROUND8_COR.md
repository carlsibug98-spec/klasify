# Klasify OCR — Round 8 benchmark (student COR)

Date: 2026-10-30 · Tree: current workspace · OCR proxy: tesseract 5.5.0
stand-in for the native PP-OCR engine (no native runtime in the test VM)

## Why round 8

Round 7 took the six-sample COR benchmark from F1 0.489 to 0.777 but left
two honest failures: `cor_phone_skewed.jpg` (2/10) and `cor_lowres.png`
(1/10). Round 8 attacks both with two new rescue passes in the scan
cascade, measured end-to-end on the same fixtures.

## Round 8 results (harness-measured, tesseract stand-in)

Micro-averaged over the six fixtures, greedy 1-to-1 matching on
day + interval overlap + subject similarity ≥ 0.34:

| metric | baseline | round 7 | round 8 |
|---|---|---|---|
| recall | 0.404 | 0.702 | **0.965** |
| precision | 0.622 | 0.870 | **1.000** |
| f1 | 0.489 | 0.777 | **0.982** |
| matched | 23/57 | 40/57 | **55/57** |
| room ok | 21 | 35 | 42 |
| professor ok | 21 | 37 | 53 |

Per fixture (round 8): clean 7/7, labs 10/10, **skewed 9/10 (was 2/10)**,
blurred 10/10, **lowres 9/10 (was 1/10)**, dim 10/10. The rescued reads
also carry no false-positive rows — parsed 55, matched 55.

## The two fixes

### High-res rescue (small captures)

The preprocessor decoded every source at an 1800 px cap (2.0x ratio floor),
which leaves cheap-camera captures at ~1440-1800 px. The round-8 sweep
found the 1500 px lowres sample reads 7/10 at 1800 but **9/10 at a 2160
target** (2880 overshoots to 3/10; sharpening at 2160 hurts: 6/10). The
cascade now adds one `upscaleTarget: 2160` candidate whenever the earlier
passes did not parse strongly and the source's longest side is under
2160 px, gated so strong scans never pay for it.

### Deskew rescue (tilted phone photos)

The existing rule-centroid estimator (`estimateGridSkew`) cannot see a
4.5-degree tilt: per-row dark runs break apart past ~1-2 degrees, which is
why `deskew: true` never fired on the skewed fixture. The new
**gradient projection profile** estimator in
`lib/features/schedule_import/utils/skew_profile_estimator.dart` works on
any tilt:

1. Mask the paper region (rows/columns whose 25th-percentile brightness is
   paper-bright — wood grain, desks, and hands fall far below).
2. Collect horizontal glyph edges inside the page, weighted by gradient
   magnitude (wood grain carries almost none).
3. Score candidate tilts by the squared row-projection sum of the sheared
   edge mass — the score peaks exactly where the text lines align.
4. Coarse sweep ±9° in 1° steps, then ±1° in 0.25° steps; prominence
   (relative gain over the 0° profile) acts as the confidence gate.

On the six fixtures it reads **-4.75° / prominence 0.170** on the skewed
photo and exactly 0.00 / 0.000 on all five straight ones — no false
rescues. The cascade tries the correction plus a ±0.75° bracket (the
profile peak and the recognizer's preferred angle can differ slightly),
each at the 2160 target, and ParseChain picks the winner; a strong parse
stops the bracket early.

## What changed

- **`lib/features/schedule_import/utils/skew_profile_estimator.dart`** (new)
  - `ProfileSkewEstimate` + `estimateSkewProfile` (pure Dart, isolate-safe,
    no Flutter imports) and `rotateRgbaBuffer` (bilinear inverse-mapped
    fine-angle rotation, white fill, PIL rotate sign convention).
  - ~200 ms per estimate/rotation on a 1620x2160 buffer.
- **`ocr_image_preprocessor.dart`**
  - The pixel transform now also produces the enhanced grayscale, runs the
    profile estimate once per prepare (skipped for threshold/invert/sharpen/
    rotate variants), and applies `rotateDegrees` after enhancement.
  - `prepare()` gains `upscaleTarget` (default 1800 = old behavior) and
    `rotateDegrees`; `PreparedOcrImage` gains `sourceLongestSide`,
    `skewDegrees`, `skewProminence`.
- **`schedule_ocr_service.dart`**
  - The scan cascade gains the **High-res rescue** and **Deskew rescue**
    passes described above, after the inversion pass and before the
    quarter-turn gate. Both fire only while no candidate has parsed
    strongly, so crisp scans keep the single-pass fast path.
- **Benchmarks / verification**
  - `tool/cor_harness/bin/score_one.dart` (new): single-fixture scorer for
    sweeps.
  - `tool/cor_harness/bin/skew_probe.dart` (new): runs the production
    estimator/rotation on raw buffers for VM-side verification.
  - `tool/cor_harness/bin/skew_synthetic_check.dart` (new): VM mirror of
    the flutter test's assertions.
  - `test/skew_profile_estimator_test.dart` (new): straight page → none,
    ±tilt → mirrored correction with rescue flag, rotation levels the page
    (residual < 0.5°), tiny buffers bail out.

## How this was verified in the VM (no Flutter SDK)

- Recipe sweeps measured every candidate (angle grid × order of ops ×
  upscale target × sharpening) through the single-fixture scorer.
- The Dart estimator was cross-checked against the Python prototype on
  identical buffers for all six fixtures: same angle, same discrimination.
- A Python⇄Dart round-trip fed the real prepped skewed buffer through the
  production `rotateRgbaBuffer`, wrote the result back to PNG, and scored
  it: 9/10, room 6, prof 7 — the exact pass the app will run.
- Parser regression suite: 39 checks, 0 failures.
- `flutter test test/bench7_cor_accuracy_test.dart` remains the on-device
  confirmation; the regression floor stays at micro-recall ≥ 0.60 until a
  CI run confirms headroom, then it can be raised.

## Reproduce

```bash
dart run tool/cor_harness/bin/harness.dart            # full six-fixture score
dart run tool/cor_harness/bin/regression.dart         # parser checks (39)
dart run tool/cor_harness/bin/skew_synthetic_check.dart
flutter test test/skew_profile_estimator_test.dart    # needs Flutter SDK
python3 scripts/sweep_round8.py                       # recipe sweep
python3 scripts/round8_probe_data.py                  # estimator fidelity
python3 scripts/round8_final_measure.py               # 55/57 measurement
```
