import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/features/auth/application/refresh_session.dart';
import 'package:klasify/features/auth/domain/entities/auth_types.dart';

import 'auth_test_fakes.dart';

void main() {
  late List<String> log;
  late FakeAuthGateway gateway;
  late FakeSessionStorage session;
  late RefreshSession refresh;

  setUp(() {
    log = [];
    gateway = FakeAuthGateway(log);
    session = FakeSessionStorage(log);
    session.storedToken = 'token-1';
    refresh = RefreshSession(gateway: gateway, session: session);
  });

  test('a missing token does nothing', () async {
    session.storedToken = null;

    expect(await refresh(), SessionRefreshStatus.noSession);
    expect(log, ['session.read-token']);
  });

  test('a refreshed session applies the new token and user', () async {
    gateway.refresh = RefreshResult.refreshed(
      token: 'token-2',
      expiresAt: '2031-01-01T00:00:00Z',
      user: authUser(1, role: 'admin'),
    );

    expect(await refresh(), SessionRefreshStatus.refreshed);

    expect(log, [
      'session.read-token',
      'gateway.refresh:token-1',
      'session.read-token',
      'session.apply-refresh',
    ]);
    expect(session.storedToken, 'token-2');
    expect(session.user?['role'], 'admin');
    expect(session.expiresAt, DateTime.parse('2031-01-01T00:00:00Z'));
  });

  test('a rejected session is cleared', () async {
    gateway.refresh = RefreshResult.rejected();

    expect(await refresh(), SessionRefreshStatus.rejected);

    expect(session.storedToken, isNull);
    expect(session.user, isNull);
    expect(log.last, 'session.clear');
  });

  test('an unreachable server keeps the session', () async {
    gateway.refresh = RefreshResult.unreachable();

    expect(await refresh(), SessionRefreshStatus.unreachable);

    expect(session.storedToken, 'token-1');
    expect(log, [
      'session.read-token',
      'gateway.refresh:token-1',
      'session.read-token',
    ]);
  });

  test('a response for a replaced token is discarded', () async {
    gateway.refresh = RefreshResult.refreshed(token: 'token-1-new');
    gateway.onRefresh = () => session.storedToken = 'token-2';

    expect(await refresh(), SessionRefreshStatus.superseded);

    expect(session.storedToken, 'token-2');
    expect(log, [
      'session.read-token',
      'gateway.refresh:token-1',
      'session.read-token',
    ]);
  });

  test('a storage failure keeps the old session', () async {
    session.failApply = true;
    gateway.refresh = RefreshResult.refreshed(token: 'token-2');

    expect(await refresh(), SessionRefreshStatus.storageFailed);

    expect(session.storedToken, 'token-1');
    expect(log.last, 'session.apply-refresh');
  });
}
