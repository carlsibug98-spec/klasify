# Round 12 — Curled-Page Rescue (warped-page auxiliary fields)

**Date:** 2026-10-31
**Question this round answers:** the round-11 generalization audit left one
Track-A gap at the top of its priority list — `cor_gen_warped.jpg` matched
10/10 rows but read only **room 3/10, prof 7/10** because the page curl
distorts the right-hand columns. Can the pipeline recover those fields
without regressing anything else?

## Diagnosis (measured, not guessed)

1. **Band fragmentation.** The curl displaces right-column words 15–48 px
   below their row's band (row 8 measured +48 px at the 1800 px scale).
   The band joiner compared every word against a *flat* running mean, so
   one table row's Schedule/Room/Faculty words fragmented onto separate
   lines — the round-11 parser then read rows without rooms, or attached
   fragments to the neighbouring row.
2. **Detection loss.** Worse: on the flattened variant tesseract stops
   *emitting* the short room tokens at all on the full page (Rm 401/402
   absent from the word list), while a crop of the right band reads every
   one of them — the glyphs are fine, the page-level sparse-text
   segmentation loses them under the local foreshortening.

## What was built (all production code; harness mirrors verbatim)

1. **Curved-row banding** (`ScheduleOcrService._joinOcrRegions` + the
   stand-in mirror): while a band holds two or more words, fit a
   least-squares tilt through the accepted word centers and also accept a
   word within tolerance of that projection. The reference never drops
   below the flat mean, so straight pages take exactly the legacy path.
2. **Region-drift gate** (`_regionColumnDrift` + mirror): left-vs-right
   column drift of the recognized word boxes, computed from the boxes the
   engine already returned (no second decode). Cross-correlation of the
   two halves' smoothed vertical center profiles; fires at
   `|drift| >= max(9 px, 0.5 x median height)` with prominence >= 1.5.
   The scan cascade **refuses to stop on a drifted pass** even when it is
   strong - the rows parse, but a curl is bending the fields.
3. **Dewarp rescue** (`OcrImagePreprocessor` isolate, `dewarp:` flag +
   cascade stage after the flatten pass): detects the page's long
   horizontal rules in 10 vertical strips, matches them bottom-up across
   strips (header underlines cannot shift the order), references each rule
   against the median across strips, and fits a linear vertical
   displacement over x. Gates: rules present in most strips, amplitude
   `>= max(6 px, 0.4 % height)` AND linear-fit residual
   `<= max(3 px, 0.25 x amplitude)`. A real curl is small *and* smooth -
   the warped fixture measures residual 0.2-0.4 px, every other fixture
   (shadows, blur, photocopy, low-res) measures 28-850 px and skips.
   Applied as `out(x, y) = in(x, y - offset(x))`, bilinear, median
   reference (every column moves by half the curl - the gentlest
   correction that levels the rows; the round-12 sweep kept all rows with
   this reference while a full left-edge correction blurred one row away),
   then the round-11 flatten recipe on the levelled rows. The candidate is
   geometry-final (`ignoreDrift`), so a strong reading stops the cascade.

## Results (tesseract stand-in cascade, production-faithful)

| fixture (Track A) | matched | room | prof | winning pass |
|---|---|---|---|---|
| cor_gen_warped.jpg (before) | 10/10 | 3 | 7 | raw / flatten |
| **cor_gen_warped.jpg (after)** | **10/10** | **6** | **9** | **dewarp (trajectory)** |

The trajectory now *delivers* the recovered reading: raw fires the drift
gate (36 px), the walk continues, and the dewarp pass stops the cascade
with all 10 rows and the recovered fields.

Full regression battery after the fix:

| suite | round-11 | round-12 |
|---|---|---|
| anchors (6 fixtures) reach | 57/57, room 55, prof 55 | **57/57, room 55, prof 57** |
| Track A (8 fixtures) reach | 80/80, room 71, prof 77 | **80/80, room 74, prof 79** |
| Track B text-readable | 25/27 | **25/27** (same two coreference misses) |
| parser regression | 39/39 | **39/39** |

No fixture regressed; the warped fixture gained room +3, prof +2, and the
anchor/Track-A auxiliary totals improved as side effects of the curved-row
joiner (deskewed tilted pages now band correctly too).

## Remaining gaps (unchanged priority order)

* **Shadow room 8/10**: two room cells sit fully inside the darkest band.
* **Grid-layout photos** need the grid scanner; device-side audit of that
  stage with the whiteboard/angled-grid fixtures.
* **Chat coreference** ("Wed same time same room") - row-carried context
  across bubbles (2 misses in `r11_chat_multi.png`).
* **Free-text dotted PM times** and the sectioned parser's compound-day
  intercept (Track C findings).
* **On-device confirmation** of the round-12 trajectory (the stand-in's
  confidences near the gates differ from the native engine; the round-10
  scorecard methodology applies).

## How to reproduce

```bash
cd klasify-cor-extracted
# the target fixture (expects ../scripts/round11_cascade.py from the
# round-11 workspace, which now carries the round-12 pass + gates)
python3 ../scripts/round11_cascade.py test/fixtures/cor_truth_gen.json \
  cor_gen_warped.jpg
# anchors
python3 ../scripts/round11_cascade.py test/fixtures/cor_truth.json \
  cor_registry_clean.png cor_labs_online.png cor_phone_skewed.jpg \
  cor_phone_blurred.png cor_lowres.png cor_dim_noise.png
# rest of Track A
python3 ../scripts/round11_cascade.py test/fixtures/cor_truth_gen.json \
  cor_gen_steep.jpg cor_gen_shadow.png cor_gen_glare.png \
  cor_gen_photocopy.png cor_gen_jpeg.jpg cor_gen_thumb.jpg \
  cor_gen_serif_clean.png
# Track B (fixtures live in bench4/)
R11_FIXDIR=test/fixtures/bench4 python3 ../scripts/round11_cascade.py \
  test/fixtures/bench4_truth_gen.json r11_notes_list.png \
  r11_planner_ampm.png r11_email_table.png r11_chat_multi.png
# regression
dart run tool/cor_harness/bin/regression.dart
```
