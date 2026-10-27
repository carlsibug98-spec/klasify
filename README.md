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
- On-device weekly class reminders with notification permission and battery-saving handling
- Android Home-screen widget integration (`NextClassWidgetService`) synced automatically on changes
- First-launch onboarding (3 pages, skippable) and replayable anytime from Settings
- Adaptive shell (`MainNavigationScreen`): floating pill navigation bar on mobile, navigation rail on wide screens (>= 600dp), and directional slide transitions
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
- **Shared widgets**: `ClassCard`, `NextClassCard`, `DayChips`, `Pill`, `EmptyStateCard`, `ErrorView`, `StatusBanner`, `TimeBox`, `SectionHeader`, `SettingsRow`, `PinnedActionBar`, `addClassFab`.

## Import a weekly timetable (offline)
1. Open **Settings** and choose **Import schedule**, or tap **Scan it** on the empty Today screen.
2. Select a PNG/JPG/WEBP image or PDF from the device.
3. Text recognition runs locally using PaddleOCR with its model assets bundled in the app; no model download or server is needed. PDF pages are rendered locally at 3x scale before OCR (up to the first 8 pages). OCR blocks are ordered using their bounding-box positions to preserve more layout information than a single flattened text string.
4. Review every detected row and edit the subject, room, day, start/end time, or professor. Missing professor values use `Not specified`; missing room values are marked `Room to confirm` and should be corrected.
5. The importer checks overlap conflicts against existing saved classes and other imported rows. Resolve conflicts before saving.
6. Confirm **Import classes**. The batch is saved in one SQLite transaction, so an insert failure rolls back the entire batch.

### Important OCR limitations
The importer supports common 12-hour and 24-hour time ranges and uses OCR text-block bounding boxes to reconstruct approximate horizontal rows. This improves common timetable grids but does not guarantee perfect column-to-weekday mapping for every school layout. Always review all detected rows. A room is not inferred from generic subject wording such as “Computer Lab Programming”; room values that are not recognized are marked Room to confirm and must be corrected before saving. Manual class cancellation is explicitly reported. The app does not silently save uncertain results; manually add missed rows or edit detected rows before importing. No image or PDF is uploaded to a server.

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

Keep both that file and the keystore out of source control. Without a release key, Gradle produces an unsigned APK that cannot be installed or published. Before publishing, replace `com.example.class_schedule` in `android/app/build.gradle.kts` with the permanent application ID you own; do not change it after the first public release.

### If Gradle reports an NDK installation error
The NDK version is controlled by the Flutter SDK's `flutter.ndkVersion` setting in `android/app/build.gradle.kts`. In Android Studio SDK Manager → SDK Tools, enable **Show Package Details** under **NDK (Side by side)** and install the exact version Flutter requests. If the package is not listed, update Android SDK Command-line Tools and retry. Do not randomly change the NDK version to a newer one; use a version supported by the installed Flutter/Android Gradle Plugin.

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
        schedule_ocr_service.dart
        timetable_grid_scanner.dart
      utils/
        timetable_parser.dart
      widgets/
        import_review_widgets.dart
  models/
    class_item.dart
  routes/
    app_router.dart
    app_routes.dart
  screens/
    backup_screen.dart
    class_form_screen.dart
    home_screen.dart
    main_navigation_screen.dart
    onboarding_screen.dart
    reminders_screen.dart
    schedule_screen.dart
    settings_screen.dart
  services/
    next_class_widget_service.dart
    onboarding_store.dart
    reminder_service.dart
  theme/
    app_theme.dart
  utils/
    next_class.dart
    schedule_backup_codec.dart
  widgets/
    app_notification.dart
    app_state_transition.dart
    class_card.dart
    class_delete_undo.dart
    class_details_sheet.dart
    component_kit.dart
    day_chips.dart
    empty_state_card.dart
    error_view.dart
    next_class_card.dart
    pill.dart
    status_banner.dart
test/
```

There is no server component. The Android `INTERNET` permission is limited to Flutter's debug and profile manifests for development tooling; it is not present in the main/release app manifest.

## Local data and safety
- Classes are stored in `class_schedule.db` on this device only.
- Android system backups exclude the schedule database and app preferences; use the in-app JSON export when moving or reinstalling the app.
- There is no online database, account, cloud sync, or backend service. OCR models are packaged with the app, and timetable images/PDFs are processed on-device.
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

## Importer improvements in this build
- OCR parsing is isolated in `lib/utils/timetable_parser.dart` so it can be unit-tested without Android OCR plugins.
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

## Full-app audit

See [`FULL_APP_AUDIT.md`](FULL_APP_AUDIT.md) for the component-by-component mapping to `components-import.html`, integration gaps, test priorities, and required device verification. This document distinguishes source implementation from behavior that has not yet been runtime-verified.
