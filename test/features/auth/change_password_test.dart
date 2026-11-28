import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/auth/application/change_password.dart';

import 'auth_test_fakes.dart';

void main() {
  late List<String> log;
  late FakeAuthGateway gateway;
  late FakeSessionStorage session;
  late ChangePassword changePassword;

  setUp(() {
    log = [];
    gateway = FakeAuthGateway(log);
    session = FakeSessionStorage(log);
    session.storedToken = 'token-1';
    session.user = authUser(1);
    changePassword = ChangePassword(gateway: gateway, session: session);
  });

  test('clears the revoked session after a successful change', () async {
    await changePassword(
      currentPassword: 'old-secret',
      newPassword: 'new-secret',
    );

    expect(log, ['gateway.change-password', 'session.clear']);
    expect(session.storedToken, isNull);
  });

  test('a rejected change keeps the session', () async {
    gateway.changePasswordError = StateError('INVALID_CREDENTIALS');

    await expectLater(
      changePassword(currentPassword: 'wrong', newPassword: 'new-secret'),
      throwsA(isA<StateError>()),
    );

    expect(log, ['gateway.change-password']);
    expect(session.storedToken, 'token-1');
  });
}
