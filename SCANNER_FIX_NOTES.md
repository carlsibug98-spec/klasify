# Timetable grid scanner regression fix

This version corrects the two geometry mistakes that caused the supplied weekly timetable to be merged incorrectly:

- Weekday columns are located from the image's vertical grid rules. The previous midpoint-only approach could start Monday at the left edge of the image and include the time gutter in Monday's column.
- Horizontal separators include both dark cell borders and high-coverage light-gray half-hour gridlines. This keeps entries such as Tuesday's IOT, B. Mallari, and MacLab in separate cells while still allowing large bordered classes to span multiple rows.
- OCR lines whose bounding boxes cross a weekday divider are skipped rather than attached to the neighboring class.
- Room and instructor extraction still runs after lines are grouped by their detected cell, so values such as `Lab2`, `Lab3`, `Room5`, `NetLab`, `MacLab`, and the recognized instructor names remain associated with the class cell.
- The weekly-grid path still avoids falling back to flattened text when it cannot map the grid reliably; it asks for manual review instead of silently guessing.

## Regression geometry checked against the supplied timetable image

The visible weekday dividers are approximately x=192, 303, 416, 525, 642, and 780 pixels. The horizontal grid rules then distinguish, among others:

- Monday RPH / Room 5: 10:30 AM–12:30 PM
- Monday PComm / Room 5 / New GE A: 12:30–1:30 PM
- Monday PE2 / Room 2 / R. Dimatulac: 2:30–4:00 PM
- Tuesday IOT: 2:00–2:30 PM
- Tuesday B. Mallari: 3:00–3:30 PM
- Tuesday QM / Room 5: 12:30–1:30 PM
- Tuesday MacLab: 4:00–4:30 PM
- Wednesday RPH Lab 2 / R. Dimatulac: 10:00–11:00 AM
- Wednesday InfoMan-Lec / NetLab: 11:30 AM–1:30 PM
- Wednesday DS and Algo / Lab 2: 2:00–5:00 PM
- Thursday Mbapp / Lab 3: 2:00–5:00 PM
- Thursday DS and Algo-Lec / Room 2: 5:00–7:00 PM
- Friday PComm / Room 5 / New GE A: 12:30–2:30 PM
- Friday QM / Room 5: 3:00–5:00 PM

The source timetable image's OCR text can vary by device and image quality, so all detected classes should still be reviewed before saving. This environment does not include the Flutter SDK, so a full `flutter analyze` / device build could not be run here.

## v36 - format variety, field hygiene, and PaddleOCR-VL 1.6

Driven by device feedback on 14 test timetables (grid, rows, calendar, list,
cards, table, dark, checklist, faculty grid, exam, time blocks, handwritten,
skew, period layouts):

- `ScheduleTextDetails`: titled professor names are matched before the bare
  initial+surname form, so "Prof." never leaks into the class name; dash runs
  ("-", "- - Prof."), month/date tokens ("Nov 07 (Thu)"), weekday words, and
  every printed time form (7-8, 7.00, 0800-0930, 11:00 - 12:30) are stripped
  from subjects; venue names without Room/Lab keywords (Main Hall, Hall A,
  Studio 1) are now recognized as rooms instead of polluting the class name;
  leftover brackets from date lines are trimmed.
- New `SectionedScheduleParser` (utils/sectioned_schedule_parser.dart): a
  format-agnostic state machine for the text path. It reads weekday header
  bands (slot mode: cells get days by column order - faculty grids, period
  rows, time-block grids), day sections ("Monday" headers), professor/period
  row markers, "No class" placeholders, exam records (weekday from the date
  line), month-calendar dates (Sunday-first grids), day-less tables, and
  single printed times (+60 min, flagged). Rows built on any assumption carry
  ocrConfidence 0.74 so the review screen flags them. Verified 1:1 against
  all 14 layouts via a Python mirror of the exact logic (scripts/mirror_*.py).
- `scanImage` no longer emits subject-only lines for list formats (the old
  routing destroyed day/time/room on re-parse and produced "no schedule
  detected"); it returns the full normalized text and the review screen runs
  the parser chain itself (sectioned first, then list, then free text).
  OCR candidate scoring now counts sectioned rows.
- Grid scanner: `labelText` strips bare-hour ranges, dotted clocks, military
  ranges, and bare "Prof" tokens; weekday headers are found via the top 22%
  fast path plus a fallback band-cluster pass, so tall title blocks no longer
  hide the header row.
- Optional PaddleOCR-VL 1.6 pass (services/paddle_ocr_vl_client.dart): the
  0.9B document-parsing VLM is free (Apache-2.0) but needs a GPU host, so the
  app can talk to a self-hosted server (URL saved in the import screen,
  SharedPreferences). Image scans try the server first and silently fall back
  to the fully offline on-device PP-OCRv6 engine - the latest offline-capable
  OCR shipped for Flutter (paddle_ocr_native 0.1.1; no newer offline model
  exists on pub.dev as of this writing). Server markdown is converted to the
  same reading-order line dump the OCR pass produces (utils/markdown_to_text.dart).
- Tests: test/sectioned_schedule_parser_test.dart (12 layout scenarios) and
  new v36 groups in test/schedule_text_parser_test.dart.

Still no Flutter toolchain in this environment; run `flutter analyze` and the
device scan checklist before shipping.
