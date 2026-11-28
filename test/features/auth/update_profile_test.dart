import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/auth/application/update_profile.dart';

import 'auth_test_fakes.dart';

void main() {
  late List<String> log;
  late FakeAuthGateway gateway;
  late FakeSessionStorage session;
  late UpdateProfile updateProfile;

  setUp(() {
    log = [];
    gateway = FakeAuthGateway(log);
    session = FakeSessionStorage(log);
    session.storedToken = 'token-1';
    session.user = authUser(1);
    updateProfile = UpdateProfile(gateway: gateway, session: session);
  });

  test('persists the updated user after the server accepts it', () async {
    final user = await updateProfile(displayName: 'Ana Updated');

    expect(user['display_name'], 'Ana Updated');
    expect(log, [
      'gateway.update:Ana Updated:null',
      'session.persist-user',
    ]);
    expect(session.user?['display_name'], 'Ana Updated');
  });

  test('a rejected update never touches the stored user', () async {
    gateway.updateError = StateError('EMAIL_EXISTS');

    await expectLater(
      updateProfile(displayName: 'Ana'),
      throwsA(isA<StateError>()),
    );

    expect(log, ['gateway.update:Ana:null']);
    expect(session.user?['display_name'], 'Ana Reyes');
  });
}
