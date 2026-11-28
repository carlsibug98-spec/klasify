import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/services/background_sync.dart';

void main() {
  tearDown(() => BackgroundSync.runnerOverride = null);

  test('the background callback runs the injected sync exactly once', () async {
    var calls = 0;
    BackgroundSync.runnerOverride = () async {
      calls++;
      return false;
    };

    final ok = await BackgroundSync.run();

    expect(ok, isFalse);
    expect(calls, 1);
  });
}
