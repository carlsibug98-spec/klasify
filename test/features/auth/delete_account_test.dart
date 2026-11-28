import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/auth/application/delete_account.dart';

import 'auth_test_fakes.dart';

void main() {
  late List<String> log;
  late FakeAuthGateway gateway;
  late FakeSessionStorage session;
  late FakeAccountScope scope;
  late DeleteAccount deleteAccount;

  setUp(() {
    log = [];
    gateway = FakeAuthGateway(log);
    session = FakeSessionStorage(log);
    session.storedToken = 'token-1';
    session.user = authUser(7);
    scope = FakeAccountScope(log);
    deleteAccount = DeleteAccount(
      gateway: gateway,
      session: session,
      scope: scope,
    );
  });

  test('a failed server delete leaves the session untouched', () async {
    gateway.deleteError = StateError('500');

    await expectLater(deleteAccount.deleteServerAccount(), throwsA(isA<StateError>()));

    expect(log, ['gateway.delete']);
    expect(session.storedToken, 'token-1');
    expect(session.user?['id'], 7);
  });

  test('a successful delete clears the session and returns the user id',
      () async {
    final userId = await deleteAccount.deleteServerAccount();

    expect(userId, 7);
    expect(log, ['gateway.delete', 'session.clear']);
    expect(session.storedToken, isNull);
    expect(session.user, isNull);
  });

  test('a user without an integer id returns null after clearing', () async {
    session.user = {'id': '7', 'display_name': 'Ana'};

    expect(await deleteAccount.deleteServerAccount(), isNull);
    expect(log, ['gateway.delete', 'session.clear']);
  });

  test('detaching is a separate step and propagates failures', () async {
    await deleteAccount.deleteServerAccount();
    await deleteAccount.detach(7);

    expect(log, ['gateway.delete', 'session.clear', 'scope.detach:7']);

    scope.detachError = StateError('rename failed');
    await expectLater(deleteAccount.detach(7), throwsA(isA<StateError>()));
  });
}
