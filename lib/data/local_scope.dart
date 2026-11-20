import 'package:flutter/foundation.dart';

/// Which SQLite file is active right now.
///
/// One file per signed-in account, plus one anonymous file for the schedule a
/// person builds before they ever sign in. The file name is the isolation
/// boundary: a query cannot reach another account's rows because the
/// connection it runs on cannot see them.
@immutable
class LocalScope {
  const LocalScope._(this.userId);

  /// The pre-login (and post-deletion) scope.
  const LocalScope.anonymous() : this._(null);

  /// The scope owned by one account.
  const LocalScope.account(int userId) : this._(userId);

  final int? userId;

  bool get isAnonymous => userId == null;

  /// The SQLite file this scope lives in.
  ///
  /// The anonymous name is the historical one on purpose: existing installs
  /// keep their data across the Klasify rename.
  String get fileName =>
      isAnonymous ? 'class_schedule.db' : 'class_schedule_u$userId.db';

  /// Stable key for prefs and backup file names.
  String get storageKey => userId?.toString() ?? 'anon';

  @override
  bool operator ==(Object other) =>
      other is LocalScope && other.userId == userId;

  @override
  int get hashCode => userId.hashCode;

  @override
  String toString() =>
      isAnonymous ? 'LocalScope.anonymous()' : 'LocalScope.account($userId)';
}
