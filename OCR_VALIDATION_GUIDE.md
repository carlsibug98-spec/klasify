# Klasify OCR validation checklist

This project keeps OCR local and uses the bundled `paddle_ocr_native` models. The import flow tries separate image variants as independent candidates, scores parsed timetable rows, and uses timetable geometry to preserve weekday/cell relationships. It does not send timetable images to a server.

## Before judging accuracy

1. Use the same set of timetable images for both the original and updated build.
2. Include clean screenshots, compressed screenshots, phone photos with perspective, faint text, small room codes, and schedules with merged cells.
3. For each image, record the correct classes manually as the ground truth: weekday, subject, start, end, room, and professor.
4. Import each image and compare detected drafts before editing or saving.
5. Count field-level errors, missed classes, duplicate classes, and incorrectly merged/split classes. Do not judge only by the number of detected rows.
6. Check that every uncertain or missing field can be corrected in the review screen before saving.

## Recommended regression cases

- The time gutter must not be assigned to Monday.
- Text crossing a weekday divider must not be attached to a neighboring day.
- Half-hour gridlines inside a larger bordered region must separate distinct short classes.
- A class spanning multiple rows must not become several classes just because its room/instructor appears on separate OCR lines.
- Missing clock labels must not change the physical row spacing.
- OCR duplicates should not produce duplicate schedule entries.
- A low-confidence but useful OCR result should not automatically beat a cleaner candidate solely because it has more raw text.
- Importing a timetable must remain a review-first operation; never silently save OCR guesses.

## Build and run checks

Run these commands from the directory containing `pubspec.yaml`:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Then test on a real Android device. OCR accuracy and processing time should be measured on-device; they cannot be established by source inspection alone.

## Offline verification

After installing the APK, enable airplane mode and import an image and a PDF stored locally on the device. Verify that recognition still works. The app's bundled OCR models should not require a first-run download. Also verify that no image or extracted schedule is transmitted by the import flow.

## Current limitations

- OCR confidence is a signal, not proof of correctness.
- Timetable layouts vary; review all detected rows before saving.
- A larger recognition model should only be integrated after the current model is benchmarked against representative real timetables. Model size alone does not guarantee better timetable accuracy.
- Curled or bent pages: the round-12 dewarp rescue straightens a page whose own horizontal rules show a smooth curl, and the cascade refuses to stop early on a page whose word boxes show left-vs-right column drift. Severely warped pages (folded, torn, or strong perspective) can still lose right-hand-column fields — review room/faculty cells on such photos carefully.
