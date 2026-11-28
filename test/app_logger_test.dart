import 'package:flutter_test/flutter_test.dart';
import 'package:klasify/services/app_logger.dart';

void main() {
  late List<String> lines;

  setUp(() {
    lines = [];
    AppLogger.sink = lines.add;
  });

  tearDown(() => AppLogger.sink = null);

  test('a log line carries level, scope and message', () {
    AppLogger.i('sync', 'Pull finished');

    expect(lines, ['INFO [sync] Pull finished']);
  });

  test('every level reaches the sink with its own prefix', () {
    AppLogger.d('backup', 'pruned');
    AppLogger.i('auth', 'restored');
    AppLogger.w('reminder', 'permission revoked');
    AppLogger.e('sync', 'failed', error: StateError('boom'));

    expect(lines, [
      'DEBUG [backup] pruned',
      'INFO [auth] restored',
      'WARN [reminder] permission revoked',
      'ERROR [sync] failed — Bad state: boom',
    ]);
  });

  test('a failing sink never throws into the caller', () {
    AppLogger.sink = (_) => throw StateError('sink down');

    expect(() => AppLogger.i('sync', 'still works'), returnsNormally);
  });
}
