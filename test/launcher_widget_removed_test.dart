import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/data/database_helper.dart';
import 'package:klasify/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // NoIsolate, like the other shell-level widget tests: the fake-async zone
    // only drains microtask-completed database work.
    sqflite.databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.databaseName =
        'launcher_widget_removed_${DateTime.now().microsecondsSinceEpoch}.db';
  });

  testWidgets('the shell does not push the schedule to a launcher widget', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('klasify/next_class_widget');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'coach_tour_shown': true,
      'first_class_coach_dismissed': true,
    });
    await tester.runAsync(() async {
      await DatabaseHelper.instance.getAll();
    });

    await tester.pumpWidget(const ScheduleApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(calls, isEmpty);
  });
}
