import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Reads the source tree and fails when a layer breaks the dependency rule.
///
/// This is intentionally a test, not a convention: the compiler cannot see
/// these boundaries, and a lint package would add build weight for one rule.
void main() {
  final root = Directory.current.path;

  List<File> dartFiles(String relative) {
    final dir = Directory(p.join(root, relative));
    if (!dir.existsSync()) return [];
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
  }

  Iterable<String> importsOf(File file) {
    final source = file.readAsStringSync();
    return RegExp(
      r'''^\s*import\s+['"]([^'"]+)['"]''',
      multiLine: true,
    ).allMatches(source).map((match) => match.group(1)!);
  }

  String relativePath(File file) =>
      p.relative(file.path, from: root).replaceAll(r'\', '/');

  test('sync domain imports only dart core and its own files', () {
    final domainDir = p.join(root, 'lib/features/sync/domain');
    final files = dartFiles('lib/features/sync/domain');
    expect(files, isNotEmpty, reason: 'The domain layer must exist.');

    for (final file in files) {
      for (final uri in importsOf(file)) {
        final where = '${relativePath(file)} imports $uri';
        if (uri.startsWith('dart:')) continue;
        expect(
          uri.startsWith('package:'),
          isFalse,
          reason: '$where; domain must not import packages.',
        );
        final resolved = p.normalize(p.join(p.dirname(file.path), uri));
        expect(
          p.isWithin(domainDir, resolved),
          isTrue,
          reason: '$where; domain must not import another layer.',
        );
      }
    }
  });

  test('sync application imports only domain and its own files', () {
    final appDir = p.join(root, 'lib/features/sync/application');
    final domainDir = p.join(root, 'lib/features/sync/domain');
    final files = dartFiles('lib/features/sync/application');
    expect(files, isNotEmpty);

    for (final file in files) {
      for (final uri in importsOf(file)) {
        final where = '${relativePath(file)} imports $uri';
        if (uri.startsWith('dart:')) continue;
        expect(
          uri.startsWith('package:'),
          isFalse,
          reason: '$where; application must stay Flutter- and package-free.',
        );
        final resolved = p.normalize(p.join(p.dirname(file.path), uri));
        expect(
          p.isWithin(appDir, resolved) || p.isWithin(domainDir, resolved),
          isTrue,
          reason: '$where; application may only import application and domain.',
        );
      }
    }
  });

  test('sync presentation does not import data or infrastructure', () {
    final files = dartFiles('lib/features/sync/presentation');
    expect(files, isNotEmpty);

    for (final file in files) {
      for (final uri in importsOf(file)) {
        final where = '${relativePath(file)} imports $uri';
        expect(
          uri.contains('/data/'),
          isFalse,
          reason: '$where; presentation must go through application/domain.',
        );
        expect(
          uri.startsWith('package:http') ||
              uri.startsWith('package:sqflite') ||
              uri.startsWith('package:flutter_secure_storage'),
          isFalse,
          reason: '$where; presentation must not touch infrastructure.',
        );
      }
    }
  });
}
