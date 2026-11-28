import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/models/event_item.dart';
import 'package:klasify/services/widget_data_actions.dart';
import 'package:klasify/theme/app_theme.dart';
import 'package:klasify/widgets/event_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The per-event switch is only half the reminder story. These tests keep the
/// form honest when the master event gate silences every event alarm.
void main() {
  // Nothing saves here, so the actions can be inert; the form only reads.
  const actions = EventActions(
    insert: _unusedInsert,
    update: _unusedUpdate,
    delete: _unusedDelete,
    restore: _unusedRestore,
  );

  Widget appUnderTest() => MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: EventSheet(actions: actions)),
      );

  Future<void> openSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(appUnderTest());
    await tester.pumpAndSettle();
  }

  testWidgets('a silenced master gate warns next to the reminder switch', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await openSheet(tester);

    expect(find.textContaining('Event alerts are off'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    // With the per-event switch off there is nothing to warn about.
    expect(find.textContaining('Event alerts are off'), findsNothing);
  });

  testWidgets('a working master gate stays quiet', (tester) async {
    SharedPreferences.setMockInitialValues({'class_reminders_enabled': true});
    await openSheet(tester);

    expect(find.textContaining('Event alerts are off'), findsNothing);
  });
}

Future<int> _unusedInsert(EventItem event) async => 1;
Future<int> _unusedUpdate(EventItem event) async => 1;
Future<int> _unusedDelete(int id) async => 1;
Future<int> _unusedRestore(EventItem event) async => 1;
