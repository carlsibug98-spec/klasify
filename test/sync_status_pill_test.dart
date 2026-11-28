import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klasify/screens/profile/profile_shared.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('a running sync says Syncing, not On', (tester) async {
    await tester.pumpWidget(
      _host(
        const SyncStatusPill(
          syncing: true,
          lastError: null,
          lastSyncAt: null,
        ),
      ),
    );

    expect(find.text('Syncing'), findsOneWidget);
    expect(find.text('On'), findsNothing);
  });

  testWidgets('a failed sync reads Off even after an earlier success', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SyncStatusPill(
          syncing: false,
          lastError: 'Network unreachable',
          lastSyncAt: DateTime(2026, 11, 28),
        ),
      ),
    );

    expect(find.text('Off'), findsOneWidget);
    expect(find.text('On'), findsNothing);
  });

  testWidgets('a successful sync reads On', (tester) async {
    await tester.pumpWidget(
      _host(
        SyncStatusPill(
          syncing: false,
          lastError: null,
          lastSyncAt: DateTime(2026, 11, 28),
        ),
      ),
    );

    expect(find.text('On'), findsOneWidget);
  });

  testWidgets('a session that never synced reads Off', (tester) async {
    await tester.pumpWidget(
      _host(
        const SyncStatusPill(
          syncing: false,
          lastError: null,
          lastSyncAt: null,
        ),
      ),
    );

    expect(find.text('Off'), findsOneWidget);
  });
}
