import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/services/theme_mode_service.dart';

void main() {
  final service = ThemeModeService.instance;

  test('system mode follows a dark platform', () async {
    await service.setMode(KlasifyThemeMode.system);

    expect(service.isDarkFor(systemIsDark: true), isTrue);
    expect(service.isDarkFor(systemIsDark: false), isFalse);
  });

  test('an explicit dark choice wins on a light platform', () async {
    await service.setMode(KlasifyThemeMode.dark);

    expect(service.isDarkFor(systemIsDark: false), isTrue);
  });

  test('an explicit light choice wins on a dark platform', () async {
    await service.setMode(KlasifyThemeMode.light);

    expect(service.isDarkFor(systemIsDark: true), isFalse);
  });
}
