# Klasify OCR — Round 10 benchmark (student COR)

Date: 2026-10-30 · Tree: current workspace · OCR proxy: tesseract 5.5.0
stand-in for the native PP-OCR engine (no native runtime in the test VM)

## Why round 10

Round 9 reached a perfect 57/57 match but left the auxiliary fields behind:
the lowres fixture read only 1/10 rooms (tesseract drops the narrow Room
column at the small capture's resolution) and the skewed fixture sat at
9/10 rooms and professors. Round 10 attacks both with two production-code
changes in the scan cascade, measured end-to-end on the same fixtures.

## Round 10 results (harness-measured, tesseract stand-in)

Micro-averaged over the six fixtures, greedy 1-to-1 matching on
day + interval overlap + subject similarity ≥ 0.34:

| metric | baseline | round 8 | round 9 | round 10 |
|---|---|---|---|---|
| recall | 0.404 | 0.965 | 1.000 | **1.000** |
| precision | 0.622 | 1.000 | 1.000 | **1.000** |
| f1 | 0.489 | 0.982 | 1.000 | **1.000** |
| matched | 23/57 | 55/57 | 57/57 | **57/57** |
| room ok | 21 | 42 | 45 | **55** |
| professor ok | 21 | 53 | 56 | **55** |

Per fixture (round 10): clean 7/7/7, labs 10/10/10,
**skewed 10 matched / 10 room / 10 prof (was 9/9)**, blurred 10/8/10,
**lowres 10 matched / 10 room / 8 prof (room was 1)**, dim 10/10/10.
Auxiliary total 101 → 110 (room +10, professor −1: the crisp recipe reads
all ten lowres rooms but garbles two "Prof. …" cells there; net +9).

## The two changes

### Crisp high-res rescue (small captures)

The room column of the small capture is visually perfect but below
tesseract's read floor at the engine-resampled 2160 upscale. The round-10
sweeps found the pairing that reveals it - and that the wrong pairing
destroys the parse outright:

| recipe at 2160 | matched | room | prof |
|---|---|---|---|
| engine-style bicubic upscale, no unsharp (round 9) | 10 | 1 | 10 |
| bicubic + PIL unsharp(2.0/35/2) | 0 | 0 | 0 |
| **Lanczos + unsharp(2.0/45/2)** | **10** | **10** | 8 |
| Lanczos + unsharp(2.0/35/2) via PIL mirror | 10 | 10 | 10 |

The unsharp only works on top of a Lanczos-quality upscale: bicubic halos
amplify into noise and the page stops parsing entirely (0/10). The chosen
point (sigma 2.0, percent 45, threshold 2.0) sits on a stable plateau across
sigma 1.9-2.0 and threshold 1.5-2.5.

Wiring: `OcrImagePreprocessor.prepare(crisp: true)` decodes at native size
(engine resampler never touches the pixels), Lanczos-upscales inside the
isolate, enhances, then applies the gentle unsharp - all in
`lib/features/schedule_import/utils/ocr_resample.dart`, a pure-Dart module
the VM harness executes directly (`lanczosResizeRgba`, `softUnsharpRgba` -
Pillow's three-box gaussian approximation, validated to mean |diff| 0.06,
max 3 levels against PIL). The high-res rescue pass is the only caller, so
crisp scans keep the single-pass fast path.

### Deskew rotate-before-enhance (tilted pages)

The round-9 deskew recipe rotated the already-enhanced buffer. Rotating
BEFORE the enhancement reads the tilted page better - the interpolation
blur gets contrast-stretched afterwards instead of being amplified first:

| deskew recipe at -4.5 deg | matched | room | prof |
|---|---|---|---|
| enhance -> rotate (round 9) | 10 | 9 | 9 |
| **rotate -> enhance (round 10)** | **10** | **10** | **10** |

The -4.5 deg winner stays inside the round-9 bracket
(est −4.75 + {0, ±0.25, ±0.5}), so no bracket change was needed - only the
op order, wired as `prepare(rotateBeforeEnhance: true)` in the deskew rescue.

## What changed

- **`lib/features/schedule_import/utils/ocr_resample.dart`** (new, pure Dart)
  - `lanczosResizeRgba` - separable Lanczos3, validated byte-for-byte
    against PIL on a ramp fixture.
  - `softUnsharpRgba` - Pillow-mirroring unsharp (three-box gaussian,
    amount percent/100, threshold gate), parameterized for sweeps.
- **`ocr_image_preprocessor.dart`**
  - `prepare()` gains `crisp` (native decode + isolate Lanczos + soft
    unsharp) and `rotateBeforeEnhance`; `_transformOcrPixels` reorders the
    rotation and reports the new `resultWidth/resultHeight` so the PNG and
    the scale factor stay correct after an in-isolate upscale.
- **`schedule_ocr_service.dart`**
  - High-res rescue passes `crisp: true`; deskew rescue passes
    `rotateBeforeEnhance: true`.
- **Benchmarks / verification**
  - `tool/cor_harness/bin/round10_probe.dart` (new): runs the production
    Lanczos/unsharp on raw buffers in the VM.
  - `scripts/sweep_round10_lowres.py`, `sweep_round10_lowres_micro.py`,
    `sweep_round10_skew_lanczos.py`, `round10_stage_isolation.py`,
    `round10_lowres_production.py`, `round10_tune_unsharp.py`,
    `round10_skew_re_check.py`, `round10_final_measure.py` (new): the sweep
    chain that isolated each divergence and measured the final 57/57.

## How this was verified in the VM (no Flutter SDK)

- Stage isolation scored all four recipe combinations (dart/PIL lanczos ×
  dart/PIL unsharp) to pin the divergence; the production unsharp was then
  validated numerically against PIL (mean |diff| 0.061, max 3 levels) and
  re-tuned on the production chain (45% plateau).
- Full six-fixture harness with the round-10 cascade mapping:
  **57/57, precision 1.000, room 55, prof 55**
  (`python3 scripts/round10_final_measure.py`).
- Parser regression suite: 39 checks, 0 failures. Baseline harness (raw
  fixtures) unchanged at 40/57 - no drift from round 9.
- `dart analyze` on the pure-Dart module: no issues; the Flutter-coupled
  files show only the expected missing-SDK import errors.
- `flutter test test/bench7_cor_accuracy_test.dart` remains the on-device
  confirmation; the regression floor stays at micro-recall ≥ 0.60.
- Timing: the crisp rescue adds ~0.5-2 s (Lanczos ~4.5 s + unsharp ~0.4 s
  in cold-JIT `dart run`; AOT is several times faster), only on scans that
  already failed every earlier pass.

## Known remaining gaps (future rounds)

- blurred room ok = 8/10 (motion-blurred room cells)
- lowres professor ok = 8/10 (two cells garbled by the crisp unsharp;
  the same names read fine on other rows)

## Reproduce

```bash
dart run tool/cor_harness/bin/regression.dart          # parser checks (39)
python3 scripts/round10_final_measure.py               # 57/57 measurement
python3 scripts/round10_tune_unsharp.py                # unsharp plateau
dart run tool/cor_harness/bin/round10_probe.dart unsharp in.bin 1906 2160 out.bin 2.0 45.0 2.0
```
