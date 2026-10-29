import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:klasify/services/first_class_coach_store.dart';

void main() {
  group('FirstClassCoachStore', () {
    test('is not dismissed on a fresh install', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await FirstClassCoachStore.isDismissed(), isFalse);
    });

    test('stays dismissed once seen', () async {
      SharedPreferences.setMockInitialValues({});
      await FirstClassCoachStore.markDismissed();
      expect(await FirstClassCoachStore.isDismissed(), isTrue);
    });
  });
}
