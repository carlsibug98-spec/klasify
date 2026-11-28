import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/auth/application/sign_in.dart';
import 'package:klasify/features/auth/domain/entities/auth_types.dart';

import 'auth_test_fakes.dart';

void main() {
  late List<String> log;
  late FakeAuthGateway gateway;
  late FakeSessionStorage session;
  late FakeAccountScope scope;
  late SignIn signIn;

  setUp(() {
    log = [];
    gateway = FakeAuthGateway(log);
    session = FakeSessionStorage(log);
    scope = FakeAccountScope(log);
    signIn = SignIn(gateway: gateway, session: session, scope: scope);
  });

  test('login switches the scope before saving the session', () async {
    final user = await signIn.login(
      email: 'ana@example.com',
      password: 'secret-123',
    );

    expect(user['id'], 1);
    expect(log, [
      'gateway.login:ana@example.com',
      'scope.ensure:1',
      'session.save',
    ]);
    expect(session.storedToken, 'token-1');
    expect(session.user?['display_name'], 'Ana Reyes');
  });

  test('a failed scope switch saves nothing and keeps the error', () async {
    scope.ensureError = StateError('disk full');

    await expectLater(
      signIn.login(email: 'ana@example.com', password: 'secret-123'),
      throwsA(
        isA<AuthScopeException>()
            .having((e) => e.error, 'error', isA<StateError>())
            .having((e) => e.stack, 'stack', isNotNull),
      ),
    );

    expect(log, ['gateway.login:ana@example.com', 'scope.ensure:1']);
    expect(session.storedToken, isNull);
    expect(session.user, isNull);
  });

  test('a user without an integer id fails before touching the scope', () async {
    gateway.response = const AuthResponse(
      token: 'token-1',
      user: {'id': '7', 'display_name': 'Ana'},
    );

    await expectLater(
      signIn.login(email: 'ana@example.com', password: 'secret-123'),
      throwsA(
        isA<AuthApiException>()
            .having((e) => e.code, 'code', 'LOCAL_SCOPE_FAILED')
            .having(
              (e) => e.message,
              'message',
              "Couldn't open the local schedule on this phone. Try again.",
            ),
      ),
    );

    expect(log, ['gateway.login:ana@example.com']);
    expect(session.storedToken, isNull);
  });

  test('register forwards the profile fields', () async {
    await signIn.register(
      email: 'ana@example.com',
      password: 'secret-123',
      displayName: 'Ana Reyes',
      department: 'CCS',
    );

    expect(log.first, 'gateway.register:ana@example.com:Ana Reyes:CCS');
  });

  test('Google sign-in never asks for profile fields', () async {
    await signIn.signInWithGoogle();

    expect(log, ['gateway.google-signin', 'scope.ensure:1', 'session.save']);
  });

  test('Google sign-up forwards the chosen profile fields', () async {
    await signIn.signUpWithGoogle(displayName: 'Ana', department: 'CCS');

    expect(log.first, 'gateway.google-signup:Ana:CCS');
  });

  test('a storage failure propagates after the scope switched', () async {
    session.failSave = true;

    await expectLater(
      signIn.login(email: 'ana@example.com', password: 'secret-123'),
      throwsA(isA<StateError>()),
    );

    expect(log, [
      'gateway.login:ana@example.com',
      'scope.ensure:1',
      'session.save',
    ]);
  });
}
