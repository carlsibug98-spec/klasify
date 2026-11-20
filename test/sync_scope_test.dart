import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:klasify/data/app_database.dart';
import 'package:klasify/data/database_helper.dart';
import 'package:klasify/services/auth_service.dart';
import 'package:klasify/services/local_scope_service.dart';
import 'package:klasify/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'scope_test_support.dart';

Map<String, dynamic> okPush({List<int> serverIds = const []}) => {
  'server_time': '2026-01-01T00:00:00.000Z',
  'classes': [
    for (var i = 0; i < serverIds.length; i++)
      {'local_id': i + 1, 'server_id': serverIds[i]},
  ],
  'events': <Object>[],
  'class_statuses': <Object>[],
};

Map<String, dynamic> okPull({Map<String, dynamic>? classRow}) => {
  'server_time': '2026-01-02T00:00:00.000Z',
  'classes': classRow == null ? <Object>[] : [classRow],
  'events': <Object>[],
  'class_statuses': <Object>[],
  'office_statuses': <Object>[],
};

Map<String, dynamic> pulledClass(String subject) => {
  'id': 42,
  'subject': subject,
  'room': 'Room 9',
  'professor': 'Prof',
  'day': 2,
  'start_minutes': 600,
  'end_minutes': 660,
  'deleted': false,
  'updated_at': '2026-01-05T00:00:00.000Z',
};

Future<void> _reply(HttpRequest request, int status, Object body) async {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await request.response.close();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
    // Sign-in must not start the background cadence: these tests drive push
    // and pull by hand.
    SyncService.autoStartEnabled = false;
  });

  late Directory dir;
  late HttpServer server;
  late Completer<void> sawPush;
  late Completer<void> sawPull;
  final pushBodies = <Map<String, dynamic>>[];
  Future<Map<String, dynamic>> Function()? pushResponder;
  Future<Map<String, dynamic>> Function()? pullResponder;

  Future<void> loginAs(int id) async {
    AuthService.testClient = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'token': 'token-$id',
          'expires_at': '2030-01-01T00:00:00Z',
          'user': {
            'id': id,
            'display_name': 'User $id',
            'email': 'u$id@example.com',
            'role': 'user',
            'department': 'CCS',
          },
        }),
        200,
      ),
    );
    await AuthService.instance.login(
      email: 'u$id@example.com',
      password: 'secret-123',
    );
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sync_scope_');
    await sqflite.databaseFactory.setDatabasesPath(dir.path);
    await LocalScopeService.instance.resetForTesting();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await AuthService.instance.logout();
    AuthService.testClient = null;

    sawPush = Completer<void>();
    sawPull = Completer<void>();
    pushResponder = null;
    pullResponder = null;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    AuthService.baseUrlOverride = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      final path = request.uri.path;
      if (path == '/sync/push') {
        final raw = await utf8.decoder.bind(request).join();
        pushBodies.add(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (!sawPush.isCompleted) sawPush.complete();
        await _reply(request, 200, await pushResponder?.call() ?? okPush());
      } else if (path == '/sync/pull') {
        await request.drain<void>();
        if (!sawPull.isCompleted) sawPull.complete();
        await _reply(request, 200, await pullResponder?.call() ?? okPull());
      } else {
        await request.drain<void>();
        await _reply(request, 404, {'error': 'No route', 'code': 'NOT_FOUND'});
      }
    });
  });

  tearDown(() async {
    AuthService.baseUrlOverride = null;
    AuthService.testClient = null;
    await AuthService.instance.logout();
    await LocalScopeService.instance.resetForTesting();
    await server.close(force: true);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('push uses the active scope device id and no cursor', () async {
    await loginAs(7);
    pushBodies.clear();

    expect(await SyncService.instance.push(), isTrue);

    expect(
      pushBodies.single['device_id'],
      await DatabaseHelper.instance.syncDeviceId(),
    );
    expect(pushBodies.single['last_push_at'], isNull);
  });

  test('push records its cursor in the scope file only', () async {
    await loginAs(7);

    expect(await SyncService.instance.push(), isTrue);

    expect(
      await DatabaseHelper.instance.lastPushAt(),
      DateTime.parse('2026-01-01T00:00:00.000Z'),
    );

    DatabaseHelper.databaseName = 'class_schedule_u8.db';
    expect(await DatabaseHelper.instance.lastPushAt(), isNull);
  });

  test('a push response that arrives after a switch writes nothing', () async {
    await loginAs(7);
    await DatabaseHelper.instance.insert(classOf('Algebra'));

    final release = Completer<void>();
    pushResponder = () async {
      await release.future;
      return okPush(serverIds: [99]);
    };

    final pending = SyncService.instance.push();
    await sawPush.future;
    await LocalScopeService.instance.ensureForUser(8);
    // Give the new scope a row, so a write that lands there is visible.
    await DatabaseHelper.instance.insert(classOf('Other'));
    release.complete();
    await pending;

    final db = await AppDatabase.instance.database;
    expect(await db.query('classes', where: 'server_id IS NOT NULL'), isEmpty);
    expect((await DatabaseHelper.instance.getAll()).single.subject, 'Other');

    await LocalScopeService.instance.ensureForUser(7);
    final db7 = await AppDatabase.instance.database;
    expect(await db7.query('classes', where: 'server_id IS NOT NULL'), isEmpty);
  });

  test('a pull that arrives after a switch writes nothing', () async {
    await loginAs(7);

    final release = Completer<void>();
    pullResponder = () async {
      await release.future;
      return okPull(classRow: pulledClass('From server'));
    };

    final pending = SyncService.instance.pull();
    await sawPull.future;
    await LocalScopeService.instance.ensureForUser(8);
    release.complete();
    await pending;

    expect(await DatabaseHelper.instance.getAll(), isEmpty);

    await LocalScopeService.instance.ensureForUser(7);
    expect(await DatabaseHelper.instance.getAll(), isEmpty);
  });

  test('sync is skipped while the scope is blocked', () async {
    await loginAs(7);
    LocalScopeService.instance.markSyncBlocked();

    expect(await SyncService.instance.syncNow(), isFalse);
  });

  test('a session that ends mid-push stops the request', () async {
    await loginAs(7);
    await LocalScopeService.instance.ensureForUser(8);
    await DatabaseHelper.instance.insert(classOf('Algebra'));

    // Change the signed-in user from inside the switch notification, so the
    // session changes while push() is between resolving the token and pinning
    // the scope. The seed hook is synchronous, so the race is deterministic.
    void listener() {
      DatabaseHelper.instance.removeListener(listener);
      AuthService.instance.debugSeedSession(
        user: const {
          'id': 8,
          'display_name': 'User 8',
          'email': 'u8@example.com',
          'role': 'user',
        },
      );
    }
    DatabaseHelper.instance.addListener(listener);
    pushBodies.clear();

    expect(await SyncService.instance.push(), isFalse);

    expect(pushBodies, isEmpty);
    expect(AuthService.instance.currentUser?['id'], 8);

    // The rows stayed in the scope they were read from; nothing was pushed.
    await LocalScopeService.instance.ensureForUser(8);
    expect((await DatabaseHelper.instance.getAll()).single.subject, 'Algebra');
  });

  test('a pull after adoption does not duplicate the adopted rows', () async {
    DatabaseHelper.databaseName = 'class_schedule.db';
    await DatabaseHelper.instance.insert(classOf('Algebra'));
    await AppDatabase.instance.closeScope('class_schedule.db');

    await loginAs(7);
    expect((await DatabaseHelper.instance.getAll()), hasLength(1));

    pushResponder = () async => okPush(serverIds: [99]);
    expect(await SyncService.instance.push(), isTrue);

    pullResponder = () async =>
        okPull(classRow: pulledClass('Algebra')..['id'] = 99);
    expect(await SyncService.instance.pull(), isTrue);

    final rows = await DatabaseHelper.instance.getAll();
    expect(rows, hasLength(1));
    expect(rows.single.subject, 'Algebra');
  });
}
