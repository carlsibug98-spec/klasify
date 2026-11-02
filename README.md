# Klasify — know what’s next

An offline-first Flutter app for maintaining a weekly class timetable. **All schedule data is stored in a local SQLite database on the device.** This project does not use Firebase, Supabase, a server, cloud sync, or online user accounts.

## Features
- Add, edit, and delete classes with instant undo capability
- Swipe left on any class row (Today list, hero, Week agenda, import review) for Edit and Delete planes; a full swipe deletes with a five-second undo toast
- Tap a class row to mark what happened to it (done / skipping / cancelled) and for how long
- Required-field, time validation, and duration calculation
- Prevent overlapping classes on the same day (adjacent classes are allowed)
- Home screen showing today's classes, remaining-class badge, and the next/in-progress class hero
- Seven-day weekly schedule with day selector strip and class count indicators
- Interactive class status sheet with per-class and multi-day status spans
- Guided five-step coach tour, shown once right after the first class is added, plus a one-time swipe hint
- Offline weekly schedule import from images/screenshots and PDF files via on-device OCR
- In-memory import draft caching (`ImportRouteCache`) allowing users to pause and resume timetable reviews
- Import review screen with conflict checks, uncertain room detection, and all-or-nothing atomic SQLite save
- JSON schedule backup and restore with structure validation and confirmation dialogs
- **Automatic backups**: a fresh backup file is written after every schedule change (no button to press). The copy lives in the app support folder and is included in Android's own device cloud backup (Google Drive) when device backup is on — still no account, no server, no internet permission
- On-device weekly class reminders with notification permission and battery-saving handling
- Android Home-screen widget integration (`NextClassWidgetService`) synced automatically on changes
- First-launch onboarding (3 pages, skippable) and replayable anytime from Settings
- Adaptive shell (`MainNavigationScreen`): floating pill navigation bar on mobile, navigation rail on wide screens (>= 600dp), directional slide transitions, and Android 14+ predictive back support
- Reusable component kit (`SectionHeader`, `SettingsRow`, `TimeBox`, `PinnedActionBar`, `KlasifySkeleton`)
- Intelligent room label formatting (`formatRoom`: normalizes `304` to `Room 304` while preserving named locations like `Lab 2` and `MacLab`)
- Real-time class status engine (`classStatusAt`: calculates `live`, `upcoming`, and `done` states relative to current minutes)
- Unit tests for schedule calculations, time formatting, input validation, and overlap rules
- Database version upgrade using validation triggers without discarding existing rows

## Weekly schedule enhancements
The weekly schedule provides a cohesive, single-day agenda experience with:
- **Responsive 7-Day Week Strip:** Scaled single-row weekday strip showing abbreviated names and date badges in a clean, uncluttered presentation.
- **Consistent Surface Styling:** App-wide card design with zero outline borders on cards, chips, badges, and controls.
- **Campus Break / Gap Dividers:** Automatic calculation and visual chips for free study and lunch windows (e.g. `1h 30m break`) with consistent symmetric 8px vertical padding.
- **Sticky Day Header & Workload Badges:** Day title and combined daily workload chip (`3 classes · 4.5h`).
- **Quick "Today" Jump:** One-tap jump button in the AppBar returning to the current day.
- **Horizontal Day Swiping:** Full-gesture day-to-day swipe navigation via `PageView`.
- **Contextual Empty States:** Direct inline *"Add class for [Day]"* action on clear days.

## UI design
The app uses a black-and-white palette: white and grey surfaces, black for text and actions. The one colour is a live orange signal, reserved for "happening now". Success, warning, and error keep their own semantic colours. All theme tokens, layout tokens, and motion tokens live in `lib/theme/app_theme.dart`.
- **Today**: a date line in the app bar, a hero block for the class in progress or the next one (the only inverted surface on the screen), and today's classes as a vertical timeline. The class in progress is marked by a live time colour. The next class in the list carries the hero's accent. Each day's remaining-class count is shown as a badge on the Today tab.
- **Week**: a seven-day selector strip (initial, date, class count) above the selected day's classes with empty-state handling.
- **Add / edit class**: sectioned fields (`Subject *`, `Room *`, optional `Professor`), weekday chips, Start/End `TimeBox` controls, and a pinned **Save class** bar. An empty professor defaults to `Not specified`.
- **Class status**: a bottom sheet per class row to mark what happened (done, skipping, cancelled) and how long it applies, with clear-status support.
- **Swipe actions**: left-swipe reveals Edit and Delete planes (mockup-parity: snap, full-swipe arm-and-release, fling velocity, haptics, reduced-motion support) on Today rows, the hero card, Week agenda rows, and import review rows.
- **Settings, Reminders, Backup, About**: grouped rows using shared `SettingsRow` on distinct surfaces with dedicated action panels; About states the version and the local-first promise and links the open-source licenses.
- **Feedback & Undo**: transient notifications use `showAppNotification` (a top toast with success, warning, error, and loading kinds). Results that stay on settings-style screens use `StatusBanner`. Deleting a class triggers an undo toast with database rollback.
- Floating Quick Actions: on mobile, a floating expandable `+` action button provides one-tap access to **Add class** or **Import schedule** (opening the importer automatically resumes an in-progress draft).
- **Navigation**: adaptive navigation uses a floating pill bar on mobile and an accessible `NavigationRail` on screens wider than 600 dp. Tabs transition using directional slide-and-fade motion, respecting system reduced-motion settings.
- **Onboarding**: three skippable pages with realistic UI previews (`lib/screens/onboarding_screen.dart`).
- **Home-screen widget**: synced via `NextClassWidgetService` to show upcoming class information on Android home screens.
- **Design Tokens**: 16px cards (`cardRadius`), 16px controls (`controlRadius`), 12px chips (`chipRadius`), 10px timeline blocks (`blockRadius`), and 28px bottom sheets (`sheetRadius`).
- **Shared widgets**: `ClassCard`, `NextClassCard`, `DayChips`, `Pill`, `EmptyStateCard`, `ErrorView`, `StatusBanner`, `TimeBox`, `SectionHeader`, `SettingsRow`, `PinnedActionBar`, `SwipeActions`, `QuickActionsButton`, `CoachTourOverlay`, `DayStatusSheet`.

## Import a weekly timetable (offline)
1. Open **Settings** and choose **Import schedule**, or tap **Scan it** on the empty Today screen.
2. Select a PNG/JPG/WEBP image or PDF from the device.
3. Text recognition runs locally using PaddleOCR with its model assets bundled in the app; no model download or server is needed. PDF pages are rendered locally at 3x scale before OCR (up to the first 8 pages). OCR blocks are ordered using their bounding-box positions to preserve more layout information than a single flattened text string.
4. Review every detected row and edit the subject, room, day, start/end time, or professor. Missing professor values use `Not specified`; missing room values are marked `Room to confirm` and should be corrected.
5. The importer checks overlap conflicts against existing saved classes and other imported rows. Resolve conflicts before saving.
6. Confirm **Import classes**. The batch is saved in one SQLite transaction, so an insert failure rolls back the entire batch.

### Important OCR limitations
The importer supports common 12-hour and 24-hour time ranges and uses OCR text-block bounding boxes to reconstruct approximate horizontal rows. This improves common timetable grids but does not guarantee perfect column-to-weekday mapping for every school layout. Always review all detected rows. A room is not inferred from generic subject wording such as “Computer Lab Programming”; room values that are not recognized are marked Room to confirm and must be corrected before saving. Manual class cancellation is explicitly reported. The app does not silently save uncertain results; manually add missed rows or edit detected rows before importing. No image or PDF is uploaded to a server.

### Student COR import
A Certificate of Registration is read by its own row parser (`CorScheduleParser`): one subject per row with its `hh:mm AM - hh:mm PM / Day` cell, room, and faculty. Photographed CORs get the same cascade as any import, plus a sharpen rescue pass that fires when the page measures soft (out-of-focus or low-res captures measure via a Laplacian variance gate, so sharp pages never pay the extra pass), an illumination-flatten pass for hard cast shadows, and a dewarp rescue that straightens a curled page when its own horizontal rules show a smooth bend (the cascade also refuses to stop early on a page whose word boxes show left-vs-right column drift, so the rescue gets its chance). Rows whose printed code column did not survive the photo are still emitted from their description and flagged for review; rooms normalize (`lab2` → `Lab 2`), and `tba`/`Online` cells are ignored. The six-sample COR accuracy benchmark and its results live in `BENCHMARK_ROUND7_COR.md` (`flutter test test/bench7_cor_accuracy_test.dart`); the generalization and curled-page rounds live in `BENCHMARK_ROUND11_GENERALIZATION.md` and `BENCHMARK_ROUND12_WARP.md`.

## Requirements
- Flutter SDK installed and available on PATH
- Android Studio with Android SDK and Android command-line tools
- A connected Android phone or Android emulator

This is an Android and iOS app. The web, Linux, macOS, and Windows platform folders were removed from this copy.

## Setup in VS Code
1. Extract the ZIP.
2. Open the **extracted project root** in VS Code — it is the folder containing `pubspec.yaml` (do not look for another nested `class_schedule` folder).
3. Open **Terminal → New Terminal**.
4. Run each command:
   ```bash
   flutter doctor -v
   flutter pub get
   flutter analyze
   flutter test
   flutter devices
   ```
5. Open Android Studio → **SDK Manager**. Under **SDK Tools**, install Android SDK Command-line Tools (latest), Android SDK Build-Tools, and NDK (Side by side). Under **SDK Platforms**, install the Android platform required by your Flutter SDK.
6. If Android SDK is installed at `C:\Android\Sdk`, configure Flutter with:
   ```powershell
   flutter config --android-sdk "C:\Android\Sdk"
   ```
   Let Flutter generate the machine-specific `android/local.properties` file. Do not share that file because it contains local SDK paths.
7. Select your Android emulator or connected phone, then run:
   ```bash
   flutter run
   ```

## Build an APK
```bash
flutter build apk --release
```
The APK is normally created at `build/app/outputs/flutter-apk/app-release.apk`.

Release builds are not signed with the debug key. To sign one, create `android/key.properties` (the example path is relative to `android/`) with your own values:

```properties
storePassword=your-keystore-password
keyPassword=your-key-password
keyAlias=upload
storeFile=app/upload-keystore.jks
```

Keep both that file and the keystore out of source control. Without a release key, Gradle produces an unsigned APK that cannot be installed or published. The application ID is `io.github.carlsibug98_spec.klasify`, set in `android/app/build.gradle.kts`. Confirm it before the first public release, because it cannot be changed after that.

### If Gradle reports an NDK installation error
The NDK version is controlled by the Flutter SDK's `flutter.ndkVersion` setting in `android/app/build.gradle.kts`. In Android Studio SDK Manager → SDK Tools, enable **Show Package Details** under **NDK (Side by side)** and install the exact version Flutter requests. If the package is not listed, update Android SDK Command-line Tools and retry. Do not randomly change the NDK version to a newer one; use a version supported by the installed Flutter/Android Gradle Plugin.

## Crash reporting (optional, off by default)
Klasify itself makes no network requests. Public distribution builds may enable opt-in crash reporting through Sentry so device-specific crashes can be found and fixed:

1. Create a free project at https://sentry.io (Flutter platform) and copy its DSN.
2. Build with the DSN compiled in:
   ```bash
   flutter build appbundle --release \
     --dart-define=KLASIFY_SENTRY_DSN=https://<key>@<org>.ingest.sentry.io/<id>
   ```
3. `docs/privacy-policy.html` documents exactly what is (and is not) transmitted.

Without the define, the Sentry SDK is never initialized, nothing is queued or sent, and the app behaves exactly as it did before crash reporting existed. Reports contain technical diagnostics only — device model, OS and app version, stack traces, timestamps — never schedule content, class names, or user identifiers. Events captured while offline are cached on disk and uploaded when connectivity returns.

## Publishing to Google Play (key gates)
- `android/app/build.gradle.kts` pins `targetSdk` and `compileSdk` to at least **36**, the level Google Play has required for new apps and updates since August 31, 2026.
- **16 KB page-size support** (required since November 1, 2025) is handled by the current Flutter + AGP 9 toolchain for the app's own code. `paddle_ocr_native` ships prebuilt ONNX Runtime libraries, so after the first release build, verify the bundle before submitting: run `python3 tool/check_16kb.py <release .apk or .aab>` (plain Python, no Android SDK needed) and cross-check Play Console's pre-launch report.
- The privacy policy lives at `docs/privacy-policy.html`. Host it publicly (GitHub Pages works), then paste the URL into the Play listing — both are mandatory. `docs/RELEASE_CHECKLIST.md` has the exact hosting recipe and the full submission runbook.
- Sign release builds via `android/key.properties` (see "Build an APK") and back the keystore up in two separate places. A lost upload key means the app can never be updated under the same listing again.
- Personal Play accounts must run a closed test with **12 testers opted in continuously for 14 days** before production access is granted. Plan the semester calendar around it.

## Project structure
```text
lib/
  main.dart
  database/
    database_helper.dart
  features/
    schedule_import/
      import_route_cache.dart
      import_schedule_screen.dart
      models/
        import_draft.dart
      services/
        ocr_image_preprocessor.dart
        schedule_ocr_service.dart
        timetable_grid_scanner.dart
      utils/                           # parsers, grid geometry, PDF helpers
        timetable_parser.dart
      widgets/
        import_review_widgets.dart
        import_source_preview_screen.dart
  models/
    class_item.dart
    class_status.dart
  routes/
    app_router.dart                    # the ONLY file that lists every screen
    app_routes.dart
  screens/
    backup_screen.dart
    edit_class_screen.dart             # add / edit class (onboarding, quick
                                       # actions, swipe planes, and import all
                                       # route here)
    home_screen.dart
    main_navigation_screen.dart
    onboarding_screen.dart
    reminders_screen.dart
    schedule_screen.dart
    settings_screen.dart
  services/
    app_info.dart
    coach_tour_store.dart
    next_class_widget_service.dart
    onboarding_store.dart
    reminder_service.dart
    swipe_hint_store.dart
  theme/
    app_theme.dart                     # light/dark themes + layout & motion tokens
    compose_colors.dart                # dark compose-mode surface tokens
  utils/
    class_text_input_rules.dart
    next_class.dart
    schedule_backup_codec.dart
    schedule_rules.dart
  widgets/                             # one file, one job (30+ widgets)
    app_notification.dart
    class_card.dart
    class_delete_undo.dart
    day_status_sheet.dart
    coach_tour_overlay.dart
    edit_class_time_picker_sheet.dart
    empty_state_card.dart
    first_run_options.dart
    next_class_card.dart
    swipe_actions.dart
    ... (see the folder for the rest)
test/
```

There is no server component. The `sentry_flutter` dependency (opt-in crash reporting) merges the Android `INTERNET` permission into release builds, but the SDK stays completely dormant unless a DSN was compiled in with `--dart-define=KLASIFY_SENTRY_DSN=...`; without it, the app opens no network connections. In debug and profile builds, Flutter development tooling additionally uses `INTERNET` as before.

## Local data and safety
- Classes are stored in `class_schedule.db` on this device only.
- Android system backups exclude the raw schedule database and app preferences (a stale database restored onto a newer schema is worse than no restore). The **automatic JSON backup** (`files/auto_backups/`) is explicitly included, so the validated, schema-safe schedule rides with Android's device cloud backup (Google Drive) when device backup is on. The manual in-app JSON export remains the way to move a schedule on demand.
- There is no online database, account, cloud sync, or backend service. OCR models are packaged with the app, and timetable images/PDFs are processed on-device. The automatic backup is written locally; any upload to Google's backup storage is performed by the operating system's own device-backup feature under the user's Google account, never by Klasify.
- Crash reporting is opt-in at build time (see "Crash reporting (optional, off by default)") and transmits technical diagnostics only, never schedule content. `docs/privacy-policy.html` is the privacy statement to publish with the app.
- Uninstalling the app may remove its local database. Back up important schedules before uninstalling or clearing app data.
- Database upgrade from version 1 to version 2 adds validation triggers without rebuilding the classes table. Existing rows are retained; invalid legacy rows are not silently dropped. New inserts/updates must meet validation rules.
- UI errors remain understandable to users; detailed failures are written to the debug console for troubleshooting.

## Checks before capstone submission
Run all of these on the development computer and resolve every reported error:
```bash
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

A ZIP/static-source review is not a substitute for running these commands on the actual Android SDK/NDK installation. The archive itself has not been claimed as build-tested unless the above commands complete successfully.

## Continuous integration
`.github/workflows/ci.yml` runs `flutter analyze` and the full `flutter test` suite on every push to `main` and every pull request, on a Windows runner with **Flutter 3.47.9** (Dart 3.13.7) and the tesseract CLI installed.

Two pins are deliberate:

- **Flutter 3.47.9** — the captures in `test/goldens/` are rendered by the Flutter engine. A different SDK re-rasterises the text and fails the design tests with 1-4% pixel drift even when no UI changed.
- **Windows** — the goldens were recorded on Windows. Linux and macOS rasterise fonts differently and will report the same drift.

Changing either pin means re-recording the goldens on the new toolchain and committing the new images in the same change:
```bash
flutter test --update-goldens test/design_capture_test.dart
```

The benchmark tests in `bench5/6/7` need the tesseract CLI and self-skip when it is missing, so CI installs it rather than silently losing that coverage.

## Importer improvements in this build
- OCR parsing is isolated in `lib/features/schedule_import/utils/timetable_parser.dart` so it can be unit-tested without Android OCR plugins.
- The parser accepts common abbreviated weekdays and can infer an omitted end AM/PM marker when the end time would otherwise be earlier than the start time.
- Identical OCR rows are deduplicated before review.
- Files larger than 20 MB are rejected to reduce memory pressure on lower-memory phones.
- Saving now wraps database reads and writes in user-facing error handling and rechecks conflicts immediately before the atomic insert.
- Rooms to confirm are explicitly flagged in the review list instead of looking like confirmed data.

## Grid-layout and manual-entry improvements
- OCR parsing now tracks standalone weekday headings so subsequent class rows without repeated weekday labels can still be recognized.
- A row containing multiple explicit weekdays (for example `Mon Wed Fri`) is expanded into separate weekly class entries.
- The review screen includes an import summary (number of candidate classes, uncertain rooms, and issue state), an explicit **Check conflicts** action, and **Add missed class** / **Add a class manually** actions.
- Grid-aware parsing remains heuristic: OCR reading order can flatten columns incorrectly. Always review the result and add missed classes manually. No importer can guarantee accurate parsing for every timetable layout without layout-specific configuration.


## Latest importer, grid, backup, and reminder work
- PDF pages render at 3x using `double` dimensions and an opaque white background before OCR.
- Weekly schedule displays a 7-day selector strip (Mon–Sun) with per-day class counts and highlights for the current day and selected day.
- JSON backup export includes a format/version marker. Restore validates all records first, asks before replacing current data, and performs replacement in one SQLite transaction.
- Backup restore rejects files larger than 2 MB or with more than 10,000 class records before replacing the schedule.
- Optional on-device weekly class reminders can be enabled in **Settings → Class reminders**. They request notification permission, use the device time zone, and schedule locally without an account or internet connection. Android can delay inexact notifications for battery saving; users should verify notification permission and battery settings on their own devices.

## Full-app audit (historical)

See [`FULL_APP_AUDIT.md`](FULL_APP_AUDIT.md) for the capstone-era (2026-10-20) component-by-component mapping to `components-import.html`. It predates the swipe-action system, the edit-class screen, and the current test suite (344 tests), so treat it as a historical snapshot rather than a description of the current app.
