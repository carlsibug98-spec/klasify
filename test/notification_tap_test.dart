import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/routes/app_routes.dart';
import 'package:klasify/services/notification_tap_service.dart';

void main() {
  test('a class reminder tap opens Today', () {
    final opened = <String>[];
    handleNotificationTap('class:12', openRoute: opened.add);

    expect(opened, [AppRoutes.home]);
  });

  test('an event reminder tap opens Today', () {
    final opened = <String>[];
    handleNotificationTap('event:9', openRoute: opened.add);

    expect(opened, [AppRoutes.home]);
  });

  test('unknown or missing payloads still open Today without throwing', () {
    final opened = <String>[];
    expect(
      () => handleNotificationTap('something-else', openRoute: opened.add),
      returnsNormally,
    );
    expect(() => handleNotificationTap(null, openRoute: opened.add), returnsNormally);
    expect(opened, [AppRoutes.home, AppRoutes.home]);
  });
}
