import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/theme/app_theme.dart';
import 'package:klasify/widgets/selected_day_header.dart';

void main() {
  testWidgets('sticky day header follows a theme change', (tester) async {
    final mode = ValueNotifier<ThemeMode>(ThemeMode.dark);
    addTearDown(mode.dispose);

    await tester.pumpWidget(
      ValueListenableBuilder<ThemeMode>(
        valueListenable: mode,
        builder: (context, value, _) => MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: value,
          home: const Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: SelectedDayHeaderDelegate(
                    dayName: 'Saturday',
                    formattedDate: 'Nov 28',
                    classCount: 0,
                    totalHours: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Material headerMaterial() => tester.widget<Material>(
      find
          .ancestor(
            of: find.text('NO CLASSES'),
            matching: find.byType(Material),
          )
          .first,
    );

    expect(headerMaterial().color, const Color(0xFF000000));

    mode.value = ThemeMode.light;
    await tester.pumpAndSettle();

    expect(headerMaterial().color, const Color(0xFFFFFFFF));
  });
}
