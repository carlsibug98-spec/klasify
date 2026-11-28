import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Reads the source tree and fails when the auth layers break the dependency
/// rule.
///
/// The compiler cannot see these boundaries, so they are pinned here exactly
/// like the sync slice: domain at the centre, application around it, data at
/// the edge, and one facade as the composition root.
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

  test('auth domain imports only dart core and its own files', () {
    final domainDir = p.join(root, 'lib/features/auth/domain');
    final files = dartFiles('lib/features/auth/domain');
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

  test('auth application imports only domain and its own files', () {
    final appDir = p.join(root, 'lib/features/auth/application');
    final domainDir = p.join(root, 'lib/features/auth/domain');
    final files = dartFiles('lib/features/auth/application');
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

  test('auth data implements the ports and stays at the edge', () {
    final files = dartFiles('lib/features/auth/data');
    expect(files, isNotEmpty, reason: 'The data layer must exist.');

    for (final file in files) {
      for (final uri in importsOf(file)) {
        final where = '${relativePath(file)} imports $uri';
        expect(
          uri.contains('/application/'),
          isFalse,
          reason: '$where; data must not depend on use cases.',
        );
        expect(
          uri.contains('/screens/') || uri.contains('/widgets/'),
          isFalse,
          reason: '$where; data must not depend on presentation.',
        );
      }
    }
  });

  test('the facade is the only composition root for auth data', () {
    final facade = 'lib/services/auth_service.dart';
    final importers = <String>[];

    for (final file in dartFiles('lib')) {
      final relative = relativePath(file);
      if (relative == facade) continue;
      if (relative.startsWith('lib/features/auth/data/')) continue;
      if (importsOf(file).any((uri) => uri.contains('features/auth/data/'))) {
        importers.add(relative);
      }
    }

    expect(
      importers,
      isEmpty,
      reason:
          'Only $facade may construct auth adapters; found: ${importers.join(', ')}',
    );
  });
}
