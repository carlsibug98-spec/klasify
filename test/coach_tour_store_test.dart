import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/services/coach_tour_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('coach tour is unshown on a fresh install', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await CoachTourStore.isShown(), isFalse);
  });

  test('coach tour remembers it was shown', () async {
    SharedPreferences.setMockInitialValues({});
    await CoachTourStore.markShown();
    expect(await CoachTourStore.isShown(), isTrue);
  });

  test('coach tour resets so Settings can replay it', () async {
    SharedPreferences.setMockInitialValues({});
    await CoachTourStore.markShown();
    expect(await CoachTourStore.isShown(), isTrue);
    await CoachTourStore.reset();
    expect(await CoachTourStore.isShown(), isFalse);
  });
}
