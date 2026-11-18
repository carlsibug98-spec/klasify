import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klasify/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('a device id is reused for the same account', () async {
    final first = await DeviceIdentity.forAccount(7);
    expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(await DeviceIdentity.forAccount(7), first);
  });

  test('signing into another account mints a new device id', () async {
    final first = await DeviceIdentity.forAccount(7);
    final second = await DeviceIdentity.forAccount(8);
    expect(second, isNot(first));

    // Coming back to the first account is another device change: the id the
    // server saw for account 7 must not be reused by account 8 or vice versa.
    final third = await DeviceIdentity.forAccount(7);
    expect(third, isNot(first));
    expect(third, isNot(second));
  });

  test('an ownerless legacy id is replaced, not claimed', () async {
    SharedPreferences.setMockInitialValues({
      'klasify_device_id': 'legacy-device-id',
    });
    final id = await DeviceIdentity.forAccount(3);
    expect(id, isNot('legacy-device-id'));
    expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
  });
}
