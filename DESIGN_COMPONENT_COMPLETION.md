# Klasify component completion pass

This pass uses `components-import.html` as the visual/behavioral reference. It expands reusable component coverage and fixes the onboarding preview to show the real “today” concept (next class + another class + navigation) rather than a simplified hero-only placeholder.

## Reusable components and behaviors now available

| Reference component / behavior | Implementation | Status |
|---|---|---|
| Class card, status, contextual actions | `lib/widgets/class_card.dart` | Implemented; supports tap, long press, edit/delete menu, optional day, today status and next-class emphasis |
| Next / in-progress class hero | `lib/widgets/next_class_card.dart`, `lib/utils/next_class.dart` | Implemented in home flow |
| Day chips | `lib/widgets/day_chips.dart` | Implemented; responsive horizontal scroll and selectable weekdays |
| Status banner / toast / undo | `status_banner.dart`, `app_notification.dart`, `class_delete_undo.dart` | Implemented; verify exact timing and visuals on device |
| Empty state / error state | `empty_state_card.dart`, `error_view.dart` | Implemented |
| Class details sheet | `class_details_sheet.dart` | Implemented |
| Add button | `add_class_fab.dart` | Implemented; narrow-screen behavior needs device validation |
| Import choose/scan/review/save flow | `features/schedule_import/` | Implemented; OCR quality and PDF/image edge cases need device validation |
| Backup/restore | `screens/backup_screen.dart`, `utils/schedule_backup_codec.dart` | Implemented; restore validation included |
| Reminders and permission handling | `screens/reminders_screen.dart`, `services/reminder_service.dart` | Implemented; platform-specific delivery depends on Android settings/permissions |
| Onboarding previews, page dots, skip/next/done | `screens/onboarding_screen.dart` | Implemented; first page now uses the richer today preview |
| Time box / picker affordance | `widgets/component_kit.dart` (`TimeBox`) | Integrated in `class_form_screen.dart` and `import_schedule_screen.dart` |
| Section heading and count | `widgets/component_kit.dart` (`SectionHeader`) | Reusable component added |
| Settings row | `widgets/component_kit.dart` (`SettingsRow`) | Reusable component added |
| Loading skeleton | `widgets/component_kit.dart` (`KlasifySkeleton`) | Reusable component added |
| Pinned bottom action bar | `widgets/component_kit.dart` (`PinnedActionBar`) | Reusable component added for long review flows |
| Destructive confirmation dialog | `widgets/component_kit.dart` (`showDeleteConfirmation`) | Reusable async confirmation helper added |
| Dark mode / safe areas / exact visual tokens | `theme/app_theme.dart` and screen layouts | Partial: uses theme/safe areas in many screens; requires screenshot-by-screenshot review against the HTML on target devices |

## Reference sections still requiring visual/device verification

The HTML contains many *states* as well as components: scan loading and failure, no-readable-timetable, import conflict/room warning, flagged-detail dialog, replace-schedule confirmation, backup restore confirmation, storage/load errors, notification permission warnings, narrow phone layout, and dark-mode variants. The app has corresponding flows or base components, but this pass does **not** claim pixel-perfect coverage for every HTML state. Confirm each state with screenshots and interaction tests on the target Android versions.

## Validation limitation

The Flutter SDK was not available in the editing environment, so `flutter analyze`, `flutter test`, and an Android build could not be run here. Source changes were checked structurally and the ZIP was integrity-checked. Run the following from `classcue_app/` on a machine with Flutter 3.44+ and Dart 3.12+:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```
