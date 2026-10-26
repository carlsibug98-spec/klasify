# Klasify full-app audit against `components-import.html`

Date: 2026-10-20

## Scope and confidence

This audit maps the HTML reference's named sections to the current Flutter source. “Source present” means a matching implementation was found in the code; it does **not** mean the screen has been visually matched or runtime-tested. Flutter/Dart executables were not available in the editing environment, so `flutter analyze`, `flutter test`, and a device build could not be run. Screenshot-based comparison also remains outstanding.

Status definitions:
- **Implemented in source** — a clear matching widget/flow exists.
- **Partial / integration gap** — some matching code exists, but the reference's full behavior, shared implementation, or all states are not established.
- **Verification required** — platform, runtime, screenshot, or real-file verification is needed before claiming completion.

## Reference coverage matrix

| HTML reference section | Flutter implementation / location | Status | Required completion / verification |
|---|---|---|---|
| Class card | `widgets/class_card.dart` | Implemented in source; verification required | Compare dimensions, status labels, overflow menu, long-press, selected/disabled states against reference. |
| Hero: next or in-progress class | `widgets/next_class_card.dart`, `utils/next_class.dart`, `screens/home_screen.dart` | Implemented in source; verification required | Verify upcoming/in-progress/ended/no-next transitions at exact time boundaries. |
| Day chips | `widgets/day_chips.dart` | Implemented in source; verification required | Check selected/today/has-classes states, horizontal scrolling, semantics, and narrow screens. |
| Time box | `widgets/component_kit.dart` (`TimeBox`), `screens/class_form_screen.dart` | Integrated in this pass; verification required | Confirm picker behavior, error styling, accessibility, and responsive sizing. |
| Fields | `screens/class_form_screen.dart` | Partial / verification required | Validate labels, required/optional fields, inline errors, focus, text scaling, and save failures. |
| Buttons | Theme and screen-specific controls | Partial / verification required | Audit all variants, sizes, loading/disabled states, and consistency against reference. |
| Navigation tab | `screens/main_navigation_screen.dart` | Implemented in source; verification required | Verify selection, badge meaning, state retention, back behavior, rail layout, and accessibility. |
| Status banner | `widgets/status_banner.dart` | Implemented in source; verification required | Verify semantic colors, wrapping, dismissal, and use on all relevant screens. |
| Notification toast | `widgets/app_notification.dart` | Implemented in source; verification required | Verify duration, queuing, semantics, and screen transitions. |
| Notification with undo | `widgets/class_delete_undo.dart` | Implemented in source; verification required | Test undo timing, repeated deletes, database failure, and reminder resynchronization. |
| Delete with undo flow | `widgets/class_delete_undo.dart`, `database/database_helper.dart` | Implemented in source; verification required | End-to-end test deletion, undo, expiration, and app lifecycle. |
| Empty state | `widgets/empty_state_card.dart`, `screens/home_screen.dart`, `screens/schedule_screen.dart` | Partial / verification required | Confirm each empty state has the correct message and reference actions, especially Today’s two actions. |
| Settings group and row | `screens/settings_screen.dart`, `widgets/component_kit.dart` | Partial; section header shared | Shared `SettingsRow` is now used in compact mode by the Settings screen; screenshot verification remains outstanding. |
| Home-screen widget | `services/next_class_widget_service.dart` | Verification required | Validate platform integration, refresh timing, empty state, and actual device presentation. |
| Class details sheet | `widgets/class_details_sheet.dart` | Implemented in source; verification required | Verify details, edit/delete actions, dismissal, safe areas, and text scaling. |
| Delete confirmation dialog | `widgets/component_kit.dart` (`showDeleteConfirmation`) plus screen-specific dialogs | Partial / integration gap | Shared helper exists, but screen-specific dialogs remain; check consistency and integrate where appropriate. |
| Error view | `widgets/error_view.dart` | Implemented in source; verification required | Confirm retry action, message quality, semantics, and use for real failures. |
| Pill labels on import drafts | `widgets/pill.dart`, `features/schedule_import/widgets/import_review_widgets.dart` | Implemented in source; verification required | Validate all draft statuses and color/label semantics. |
| Notification: warning and loading | `widgets/status_banner.dart`, `widgets/app_notification.dart`, import/reminder screens | Partial / verification required | Verify loading and warning states are connected to real service state, not only appearance. |
| Import: choose a timetable | `features/schedule_import/import_schedule_screen.dart` | Implemented in source; verification required | Test file picker cancellation, unsupported files, permissions, and selection. |
| Import: selected file | `features/schedule_import/import_schedule_screen.dart`, `import_source_preview_screen.dart` | Implemented in source; verification required | Verify preview accuracy, multi-page PDFs, large files, and replacement of selected files. |
| Import: scanning | `schedule_ocr_service.dart`, `timetable_grid_scanner.dart`, import screen | Implemented in source; verification required | Test cancellation, long scans, resource limits, and UI responsiveness on physical devices. |
| Import scan result messages | Import screen and `import_review_widgets.dart` | Partial / verification required | Test zero detections, partial detections, unreadable pages, and successful extraction. |
| Import attention banner | `import_review_widgets.dart` | Implemented in source; verification required | Ensure warnings are computed from draft data and clearly explain required action. |
| Import summary cards | `import_review_widgets.dart` | Implemented in source; verification required | Cross-check counts against actual draft list and filtering behavior. |
| Import draft card | `import_review_widgets.dart`, `models/import_draft.dart` | Implemented in source; verification required | Verify editing, deleting, warnings, incomplete fields, and long text. |
| Import original timetable | `import_source_preview_screen.dart` | Implemented in source; verification required | Test source preview alignment, page selection, and memory use. |
| Import result messages | Import screen | Partial / verification required | Verify success/error wording reflects the actual persistence result. |
| Backup action panel | `screens/backup_screen.dart` | Implemented in source; verification required | Test file picker behavior and exported content on target platforms. |
| Reminders switch panel | `screens/reminders_screen.dart`, `services/reminder_service.dart` | Implemented in source; device verification required | Test permission denial, exact alarm access, schedule/unschedule, reboot and app lifecycle. |
| Onboarding preview, dots, button | `screens/onboarding_screen.dart` | Implemented in source; visual verification required | Compare all four previews and page controls against the reference at matching sizes. |
| Week day tile and date header | `screens/schedule_screen.dart` | Implemented in source; visual verification required | Verify date transitions, selection states, locale behavior, and narrow layouts. |
| Section header with count | `widgets/component_kit.dart`; Settings group uses `SectionHeader` | Partially integrated | Integrate in other matching production sections where it improves consistency; compare typography and spacing. |
| More menu on class card | `widgets/class_card.dart` | Implemented in source; verification required | Verify edit/delete actions, dismiss behavior, and accessibility. |
| Pinned action bar | `widgets/component_kit.dart`; class form has its own pinned bar | Partial / integration gap | Unify shared bar API with destructive/secondary actions, then integrate into import review where appropriate. |
| Loading | Home/import/reminders screens | Partial / verification required | Audit all asynchronous operations for progress indication, duplicate submissions, cancellation, and stale results. |
| Skeleton | `widgets/component_kit.dart` (`KlasifySkeleton`) | Component exists; integration gap | Use only where loading placeholders match the reference; otherwise avoid replacing clear progress indicators. |
| Storage / load error | Database, home, backup, import flows | Partial / verification required | Force database read/write failures and verify recovery actions and preserved user input. |
| Dark-mode notes | `theme/app_theme.dart` | Verification required | Confirm whether dark mode is intended; if supported, test every screen and semantic state. |
| Safe areas | Many screens use `SafeArea`; shared bar uses it | Partial / verification required | Inspect bottom bars, dialogs, sheets, landscape, gesture navigation, and cutouts on device. |
| Settings: two groups | `screens/settings_screen.dart` | Implemented in source; visual verification required | Compare group headings, row heights, dividers, icons, and wrapping. |
| Reminders screen | `screens/reminders_screen.dart` | Implemented in source; device verification required | Validate settings state and permission recovery against actual Android versions. |
| Replace current schedule (backup restore) | `screens/backup_screen.dart` | Implemented in source; verification required | Test cancellation, malformed backup, valid restore, atomic replacement, and notification sync failure. |
| Replace saved classes (import) | Import flow | Verification required | Confirm exact merge/replace semantics and ensure no data changes before confirmation. |
| Empty Today: two actions | Home screen and empty-state widgets | Verification required | Explicitly compare both actions and their navigation to the HTML reference. |
| Import review primary button variants | Import review widgets/screen | Partial / verification required | Verify labels and enabled state for zero, valid, flagged, and saving drafts. |
| Onboarding last page on replay | `screens/onboarding_screen.dart`, Settings route | Implemented in source; verification required | Confirm replay closes instead of restarting onboarding and does not reset first-run state. |
| Import conflict and file messages | Import parser/review flow | Partial / verification required | Test overlapping classes, duplicate drafts, unreadable files, and actionable conflict messages. |
| Load and save errors | Home, class form, backup, import | Partial / verification required | Inject failures; ensure typed input/drafts remain available and success is never reported prematurely. |
| Import review header and summary | `import_review_widgets.dart` | Implemented in source; verification required | Verify counts, source name, and warning state update when drafts are edited. |
| Import review room warning | Import review widgets | Implemented in source; verification required | Check placeholder room recognition and that warning clears after correction. |
| Import review flagged details dialog | Import review widgets | Implemented in source; verification required | Test open/close, focus, accessible warning details, and long content. |
| Import review action bar | Import screen and component kit | Partial / integration gap | Align the real review bar with the shared pinned action bar and all button variants. |
| Add button on narrow phones | `widgets/add_class_fab.dart` | Verification required | Screenshot and interaction test at smallest supported widths and large text. |
| Import: how to save | Import screen | Verification required | Test all save choices, cancellation, replacement, and database failures. |
| Reminder permission warnings | `screens/reminders_screen.dart`, `services/reminder_service.dart` | Implemented in source; device verification required | Test denied notification permission and exact-alarm access on each supported Android version. |
| Timetable could not be read | OCR service/import screen | Partial / verification required | Test real unreadable images/PDFs and make recovery steps specific and actionable. |

## Cross-app findings and actions taken in this pass

1. **Integrated the shared `TimeBox` into the real class form.** The form no longer uses a separate private time-field widget. The shared control now supports placeholder and error styling and includes an accessible error-state label.
2. **Integrated the shared `SectionHeader` into Settings group headings.** This reduces one source of visual divergence.
3. **Added a widget test** for the TimeBox error-state semantics.
4. **Unified Settings rows.** The Settings screen now uses `SettingsRow(compact: true)` instead of maintaining a duplicate private row widget. Other local variants should be unified only after confirming their reference appearance and required actions.

## Highest-priority unresolved work

1. Run Flutter format/analyze/test and a debug build with the required Flutter/Dart SDK.
2. Create screenshot comparisons for every major screen and responsive breakpoint.
3. Add end-to-end tests for class CRUD + undo, import review/save/replace, backup/restore, and reminders.
4. Validate OCR with a diverse set of real timetable photos and PDFs with expected output records.
5. Test notification delivery, permission denial, exact alarms, reboot, and schedule changes on real Android devices.
6. Complete accessibility checks for large text, screen readers, keyboard/focus, touch targets, and semantic state.
7. Resolve the remaining private/shared component duplicates after screenshot comparison.

## Reproducible verification commands

Run from `classcue_app/` with Flutter 3.44+ and Dart 3.12+:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Then perform manual device checks for file picker, OCR, notification permissions, exact alarms, restore, safe areas, and narrow-width layouts. Until these steps pass, this audit deliberately does not claim the app is complete or pixel-perfect.
