import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/services/auth_service.dart';

typedef _Handler = Future<void> Function(HttpRequest request);

Future<void> _reply(HttpRequest request, int status, Object body) async {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await request.response.close();
}

void main() {
  late HttpServer server;
  late _Handler handler;
  late bool serverClosed;
  final requests = <({String method, String path, String? auth})>[];

  Future<void> signIn() async {
    handler = (request) => _reply(request, 200, {
      'token': 'token-1',
      'expires_at': '2030-01-01T00:00:00Z',
      'user': {
        'id': 1,
        'display_name': 'Ana Reyes',
        'email': 'ana@example.com',
        'role': 'user',
        'department': 'CCS',
      },
    });
    await AuthService.instance.login(
      email: 'ana@example.com',
      password: 'secret-123',
    );
    expect(AuthService.instance.token, 'token-1');
    requests.clear();
  }

  setUp(() async {
    // The plugin's own in-memory platform: real SessionStore reads/writes,
    // no method channel and no app-level test double.
    FlutterSecureStorage.setMockInitialValues({});
    await AuthService.instance.logout();
    AuthService.testClient = null;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    serverClosed = false;
    AuthService.baseUrlOverride = 'http://127.0.0.1:${server.port}';
    requests.clear();
    handler = (request) =>
        _reply(request, 404, {'error': 'No route', 'code': 'NOT_FOUND'});
    server.listen((request) async {
      requests.add((
        method: request.method,
        path: request.uri.path,
        auth: request.headers.value('authorization'),
      ));
      // Drain the body so the connection is reusable between calls.
      await request.drain<void>();
      await handler(request);
    });
  });

  tearDown(() async {
    AuthService.baseUrlOverride = null;
    await AuthService.instance.logout();
    if (!serverClosed) await server.close(force: true);
  });

  test(
    'refresh persists the new token and the refreshed user payload',
    () async {
      await signIn();
      handler = (request) => _reply(request, 200, {
        'token': 'token-2',
        'expires_at': '2031-01-01T00:00:00Z',
        'user': {
          'id': 1,
          'display_name': 'Ana Reyes',
          'email': 'ana@example.com',
          'role': 'admin',
          'department': 'CCS',
        },
      });

      expect(await AuthService.instance.refreshSession(), isTrue);

      expect(AuthService.instance.token, 'token-2');
      expect(AuthService.instance.isAdmin, isTrue);
      expect(AuthService.instance.displayName, 'Ana Reyes');
      expect(requests, hasLength(1));
      expect(requests.single.path, '/auth/refresh');
      expect(requests.single.auth, 'Bearer token-1');

      final stored = await const FlutterSecureStorage().read(
        key: 'klasify_auth_token',
      );
      expect(stored, 'token-2');
    },
  );

  test('a malformed 200 keeps the current session', () async {
    await signIn();
    // token is not a String: parsing fails after a 200, which must behave
    // like an unreachable server rather than signing the user out.
    handler = (request) => _reply(request, 200, {'token': 42});

    expect(await AuthService.instance.refreshSession(), isFalse);

    expect(AuthService.instance.isLoggedIn, isTrue);
    expect(AuthService.instance.token, 'token-1');
    final stored = await const FlutterSecureStorage().read(
      key: 'klasify_auth_token',
    );
    expect(stored, 'token-1');
  });

  test('a rejected refresh clears the persisted session', () async {
    await signIn();
    handler = (request) => _reply(request, 401, {
      'error': 'Session expired',
      'code': 'INVALID_TOKEN',
    });

    expect(await AuthService.instance.refreshSession(), isFalse);

    expect(AuthService.instance.isLoggedIn, isFalse);
    expect(AuthService.instance.token, isNull);
    final storage = const FlutterSecureStorage();
    expect(await storage.read(key: 'klasify_auth_token'), isNull);
    expect(await storage.read(key: 'klasify_auth_user'), isNull);
    expect(await storage.read(key: 'klasify_auth_expires_at'), isNull);
  });

  test('an unreachable server keeps the current session', () async {
    await signIn();
    await server.close(force: true);
    serverClosed = true;

    expect(await AuthService.instance.refreshSession(), isFalse);

    expect(AuthService.instance.isLoggedIn, isTrue);
    expect(AuthService.instance.token, 'token-1');
  });

  test(
    'a 401 TOKEN_EXPIRED refreshes once and retries with the new token',
    () async {
      await signIn();
      var meCalls = 0;
      var refreshCalls = 0;
      final seenAuth = <String?>[];
      handler = (request) async {
        switch (request.uri.path) {
          case '/auth/me':
            meCalls++;
            seenAuth.add(request.headers.value('authorization'));
            if (meCalls == 1) {
              await _reply(request, 401, {
                'error': 'Token expired',
                'code': 'TOKEN_EXPIRED',
              });
              return;
            }
            await _reply(request, 200, {
              'user': {
                'id': 1,
                'display_name': 'Ana Updated',
                'email': 'ana@example.com',
                'role': 'user',
                'department': 'CCS',
              },
            });
            return;
          case '/auth/refresh':
            refreshCalls++;
            await _reply(request, 200, {
              'token': 'token-2',
              'expires_at': '2031-01-01T00:00:00Z',
            });
            return;
          default:
            await _reply(request, 404, {
              'error': 'No route',
              'code': 'NOT_FOUND',
            });
            return;
        }
      };

      final user = await AuthService.instance.updateProfile(
        displayName: 'Ana Updated',
      );

      expect(user['display_name'], 'Ana Updated');
      expect(meCalls, 2);
      expect(refreshCalls, 1);
      expect(seenAuth, ['Bearer token-1', 'Bearer token-2']);
      expect(AuthService.instance.token, 'token-2');
      expect(AuthService.instance.displayName, 'Ana Updated');
    },
  );

  test(
    'a second TOKEN_EXPIRED after the refresh throws instead of looping',
    () async {
      await signIn();
      var meCalls = 0;
      var refreshCalls = 0;
      handler = (request) async {
        switch (request.uri.path) {
          case '/auth/me':
            meCalls++;
            await _reply(request, 401, {
              'error': 'Token expired',
              'code': 'TOKEN_EXPIRED',
            });
            return;
          case '/auth/refresh':
            refreshCalls++;
            await _reply(request, 200, {
              'token': 'token-2',
              'expires_at': '2031-01-01T00:00:00Z',
            });
            return;
          default:
            await _reply(request, 404, {
              'error': 'No route',
              'code': 'NOT_FOUND',
            });
            return;
        }
      };

      await expectLater(
        AuthService.instance.updateProfile(displayName: 'Still Expired'),
        throwsA(
          isA<AuthApiException>().having(
            (e) => e.code,
            'code',
            'TOKEN_EXPIRED',
          ),
        ),
      );

      expect(meCalls, 2);
      expect(refreshCalls, 1);
    },
  );
}
