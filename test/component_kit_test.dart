import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/widgets/component_kit.dart';

void main() {
  testWidgets('TimeBox shows label and selected time', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimeBox(label: 'Starts', value: '9:00 AM', onTap: () {}),
        ),
      ),
    );
    expect(find.text('Starts'), findsOneWidget);
    expect(find.text('9:00 AM'), findsOneWidget);
  });

  testWidgets('TimeBox exposes error state accessibly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimeBox(
            label: 'End',
            value: 'Select',
            isPlaceholder: true,
            hasError: true,
            onTap: () {},
          ),
        ),
      ),
    );
    expect(
      find.bySemanticsLabel(RegExp(r'End,\s+Select,\s+invalid')),
      findsOneWidget,
    );
  });

  testWidgets('SectionHeader displays title and count', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SectionHeader(title: 'Monday', count: 3)),
      ),
    );
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('SettingsRow supports subtitle and trailing control', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SettingsRow(
            title: 'Reminders',
            subtitle: '10 minutes before class',
            trailing: Switch(value: true, onChanged: null),
          ),
        ),
      ),
    );
    expect(find.text('Reminders'), findsOneWidget);
    expect(find.text('10 minutes before class'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('PinnedActionBar disables primary while busy', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          bottomNavigationBar: PinnedActionBar(
            primaryLabel: 'Save',
            onPrimary: null,
            busy: true,
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('PinnedActionBar decoration has no top border outline', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          bottomNavigationBar: PinnedActionBar(
            primaryLabel: 'Save',
            onPrimary: null,
          ),
        ),
      ),
    );
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(PinnedActionBar),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration as BoxDecoration?;
    expect(decoration?.border, isNull);
  });
}
