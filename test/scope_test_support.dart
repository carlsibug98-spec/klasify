import 'dart:io';

import 'package:klasify/data/database_helper.dart';
import 'package:klasify/models/class_item.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

/// Creates an empty directory and points sqflite at it.
///
/// Each suite owns its directory so a crashed earlier run cannot leave a row
/// behind that the next run trips over.
Future<Directory> freshDatabasesPath(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  await sqflite.databaseFactory.setDatabasesPath(dir.path);
  return dir;
}

/// Closes every cached connection, then removes the suite's directory.
///
/// Windows refuses to delete a file that still has an open handle, so the
/// close has to happen before teardown.
Future<void> disposeDatabasesPath(Directory dir) async {
  await DatabaseHelper.instance.resetForTesting();
  await deleteDirectoryWithRetry(dir);
}

/// Deletes a directory, retrying while a background writer still holds it.
///
/// A service that debounces a file write can still be flushing when the test
/// body ends. Windows keeps the handle open until that write closes, so the
/// first delete throws `errno = 32`; waiting briefly is enough.
Future<void> deleteDirectoryWithRetry(
  Directory dir, {
  int attempts = 20,
  Duration delay = const Duration(milliseconds: 50),
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (!await dir.exists()) return;
    try {
      await dir.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == attempts - 1) rethrow;
      await Future<void>.delayed(delay);
    }
  }
}

/// Drops every cached connection and returns the app to the pre-login file.
Future<void> resetLocalData() async {
  await DatabaseHelper.instance.resetForTesting();
  DatabaseHelper.databaseName = 'class_schedule.db';
}

/// A minimal row that passes the class CHECK constraints.
ClassItem classOf(String subject, {int day = 1, int startMinutes = 480}) =>
    ClassItem(
      subject: subject,
      room: 'Room 1',
      professor: 'Prof',
      day: day,
      startMinutes: startMinutes,
      endMinutes: startMinutes + 60,
    );
