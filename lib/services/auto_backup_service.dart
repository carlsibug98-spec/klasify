import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database_helper.dart';
import '../data/local_scope.dart';
import '../utils/schedule_backup_codec.dart';
import 'local_scope_service.dart';

/// Quietly keeps a fresh schedule backup on disk after every schedule change.
///
/// Klasify only talks to a server when you sign in; this backup is
/// deliberately independent of that. "The cloud" here is the phone's own
/// mechanism: the backup lives in the app's support directory, which Android
/// includes in its device cloud backup (Google Drive) whenever the user has
/// device backup on. The schedule therefore reaches the user's Google cloud
/// automatically — while Klasify itself sends nothing for this backup.
///
/// The newest copy is always `klasify-auto-backup.json`. Up to
/// [datedCopiesToKeep] dated siblings roll behind it (one per minute at
/// most) so a corrupt write can never strand the user. Writes are atomic
/// (temp file + rename) and every failure is recorded in [lastError] instead
/// of surfacing as a crash; the next schedule change retries.
class AutoBackupService extends ChangeNotifier {
  /// The app always talks to [instance]; tests may build isolated instances.
  AutoBackupService();

  static final AutoBackupService instance = AutoBackupService();

  static const String _enabledKeyBase = 'auto_backup_enabled';
  static const String _lastAtKeyBase = 'auto_backup_last_at';
  static const String _lastCountKeyBase = 'auto_backup_last_count';

  /// The always-current backup file inside the backup directory.
  ///
  /// One per scope: a signed-in account's backup must not be overwritten by
  /// another account on the same phone.
  static String get mainFileName =>
      mainFileNameFor(LocalScopeService.instance.current);

  /// Dated rolling copies are `<prefix><yyyyMMdd-HHmm>.json`.
  static String get datedPrefix =>
      datedPrefixFor(LocalScopeService.instance.current);

  static String mainFileNameFor(LocalScope scope) => scope.isAnonymous
      ? 'klasify-auto-backup.json'
      : 'klasify-auto-backup-u${scope.userId}.json';

  static String datedPrefixFor(LocalScope scope) => scope.isAnonymous
      ? 'klasify-backup-'
      : 'klasify-backup-u${scope.userId}-';

  /// Prefs keys for the active scope, so a second account neither inherits
  /// the first one's toggle nor reports its last-write stamp.
  String get _enabledKey => _scopeKey(_enabledKeyBase);
  String get _lastAtKey => _scopeKey(_lastAtKeyBase);
  String get _lastCountKey => _scopeKey(_lastCountKeyBase);

  String _scopeKey(String base, [LocalScope? scope]) {
    final userId = (scope ?? LocalScopeService.instance.current).userId;
    return userId == null ? base : '${base}_u$userId';
  }

  /// Rolling window behind the main file (6 dated copies ≈ a busy day).
  static const int datedCopiesToKeep = 6;

  static const String directoryName = 'auto_backups';

  /// Tests point this at a temporary directory.
  @visibleForTesting
  static Future<Directory> Function() documentsDirectoryResolver =
      getApplicationSupportDirectory;

  /// Quiet time between a schedule change and the write, so a burst of
  /// edits (import review, drag, undo) collapses into one backup.
  @visibleForTesting
  static Duration debounceDelay = const Duration(milliseconds: 1500);

  /// Reads the active scope. Tests use it to simulate an account switch
  /// between the capture and the database reads.
  @visibleForTesting
  static LocalScope Function() scopeReader =
      () => LocalScopeService.instance.current;

  Timer? _debounce;
  bool _running = false;
  bool _pending = false;
  bool _loaded = false;
  bool _attached = false;
  bool _enabled = true;
  int? _lastClassCount;
  DateTime? _lastBackupAt;
  String? _lastError;

  /// Whether automatic backups are on. On is the default — the user should
  /// have to opt out of safety, not into it.
  bool get enabled => _enabled;

  /// Class count captured by the last successful backup.
  int? get lastClassCount => _lastClassCount;

  /// When the last successful backup finished (local time).
  DateTime? get lastBackupAt => _lastBackupAt;

  /// Human-readable reason the last attempt failed, or null.
  String? get lastError => _lastError;

  /// True while a backup is being written (or waiting to).
  bool get busy => _running || _pending;

  /// Loads persisted state. Safe to call more than once; [attach] calls it.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledKey) ?? true;
      final ms = prefs.getInt(_lastAtKey);
      _lastBackupAt = ms == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(ms);
      _lastClassCount = prefs.getInt(_lastCountKey);
    } catch (e, st) {
      debugPrint('Auto backup: could not load state, using defaults: $e\n$st');
    }
  }

  /// Subscribes to schedule changes and refreshes the quiet copy on launch.
  ///
  /// Safe to call more than once; only the first call binds the listener.
  Future<void> attach() async {
    await load();
    if (_attached) return;
    _attached = true;
    DatabaseHelper.instance.addListener(_onScheduleChanged);
    // Fresh launch: refresh the copy so a crash or a restored database can
    // never leave the backup older than the real schedule.
    scheduleBackup();
  }

  /// Re-reads persisted state for the scope that just became active.
  ///
  /// A switch must not report the previous account's last-write stamp or
  /// carry its toggle into the new scope.
  Future<void> notifyScopeChanged() async {
    _loaded = false;
    await load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_attached) DatabaseHelper.instance.removeListener(_onScheduleChanged);
    _attached = false;
    super.dispose();
  }

  void _onScheduleChanged() => scheduleBackup();

  /// Queues a debounced backup. Collapses naturally while edits continue.
  void scheduleBackup() {
    if (!_enabled) return;
    _debounce?.cancel();
    _debounce = Timer(debounceDelay, () async {
      _pending = false;
      await backupNow();
    });
  }

  /// Turns automatic backups on or off and persists the choice.
  ///
  /// Turning it on takes a backup immediately; turning it off cancels any
  /// queued write but never deletes existing backup files.
  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (e, st) {
      debugPrint('Auto backup: could not persist the toggle: $e\n$st');
    }
    if (value) {
      _debounce?.cancel();
      _pending = false;
      await backupNow();
    } else {
      _debounce?.cancel();
      _pending = false;
    }
  }

  /// Writes the backup now (unless disabled). Returns true on success.
  ///
  /// Re-entrant calls collapse into a single follow-up write instead of
  /// stacking parallel disk work.
  Future<bool> backupNow() async {
    if (!_enabled) return false;
    if (_running) {
      _pending = true;
      return false;
    }
    _running = true;
    // Capture the scope once. The schedule is read from the active file and
    // the backup must be named for that same file: a switch between the read
    // and the write must not store A's schedule under B's backup name.
    final scope = scopeReader();
    notifyListeners();
    var ok = false;
    try {
      final classes = await DatabaseHelper.instance.getAll();
      final events = await DatabaseHelper.instance.getAllEvents();
      // The name was captured before the reads. If the active file changed
      // while they ran, these rows belong to the other account: writing them
      // now would put B's schedule in A's file. The new scope's own change
      // or launch hook writes the correct backup instead.
      if (scopeReader() != scope) {
        debugPrint('Auto backup: scope changed during the read, skipped.');
        return false;
      }
      final bytes = ScheduleBackupCodec.encode(classes, events: events);
      final dir = await _ensureDirectory();
      final now = DateTime.now();
      final main = mainFileNameFor(scope);
      final prefix = datedPrefixFor(scope);
      await _atomicWrite(File(p.join(dir.path, main)), bytes);
      await _atomicWrite(
        File(p.join(dir.path, '$prefix${_stamp(now)}.json')),
        bytes,
      );
      await _rotate(dir, prefix);
      _lastClassCount = classes.length;
      _lastBackupAt = now;
      _lastError = null;
      ok = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
          _scopeKey(_lastAtKeyBase, scope),
          now.millisecondsSinceEpoch,
        );
        await prefs.setInt(
          _scopeKey(_lastCountKeyBase, scope),
          classes.length,
        );
      } catch (e) {
        debugPrint('Auto backup: could not persist the stamp: $e');
      }
    } catch (e, st) {
      _lastError = e.toString();
      debugPrint('Automatic backup failed: $e\n$st');
    } finally {
      _running = false;
      notifyListeners();
    }
    return ok;
  }

  /// Deletes every backup file belonging to a scope.
  ///
  /// Called when the account that owned them is deleted. Another account's
  /// files are never touched: the prefix is exact, not a substring.
  Future<void> deleteScopeBackups(LocalScope scope) async {
    if (scope.isAnonymous) return;
    final dir = await _ensureDirectory();
    final main = mainFileNameFor(scope);
    final prefix = datedPrefixFor(scope);
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final owned = name == main || (name.startsWith(prefix) && name.endsWith('.json'));
      if (!owned) continue;
      try {
        await entity.delete();
      } catch (e) {
        debugPrint('Auto backup: could not remove ${entity.path}: $e');
      }
    }
  }

  /// Forgets the prefs a scope stored, once that scope no longer exists.
  Future<void> forgetScope(LocalScope scope) async {
    if (scope.isAnonymous) return;
    final prefs = await SharedPreferences.getInstance();
    for (final base in const [
      _enabledKeyBase,
      _lastAtKeyBase,
      _lastCountKeyBase,
    ]) {
      await prefs.remove('${base}_u${scope.userId}');
    }
  }

  /// The current backup file, or null when nothing has been written yet.
  Future<File?> loadMainBackupFile() async {
    try {
      final dir = await _ensureDirectory();
      final file = File(p.join(dir.path, mainFileName));
      if (await file.exists()) return file;
    } catch (e, st) {
      debugPrint('Auto backup: could not read the backup file: $e\n$st');
    }
    return null;
  }

  Future<Directory> _ensureDirectory() async {
    final base = await documentsDirectoryResolver();
    final dir = Directory(p.join(base.path, directoryName));
    await dir.create(recursive: true);
    return dir;
  }

  /// Write-then-rename so a killed process never leaves a half-written JSON.
  Future<void> _atomicWrite(File target, List<int> bytes) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
  }

  /// Keeps only the newest [datedCopiesToKeep] dated copies of this scope.
  ///
  /// The match is anchored and exact: the anonymous prefix is a string
  /// prefix of an account's, so a loose `startsWith` would let one scope
  /// delete another's rolling copies.
  Future<void> _rotate(Directory dir, String prefix) async {
    final pattern = RegExp(
      '^${RegExp.escape(prefix)}\\d{8}-\\d{4}\\.json\$',
    );
    final copies = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (pattern.hasMatch(name)) {
          copies.add(entity);
        }
      }
    }
    copies.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    for (final stale in copies.skip(datedCopiesToKeep)) {
      try {
        await stale.delete();
      } catch (e) {
        debugPrint('Auto backup: could not remove ${stale.path}: $e');
      }
    }
  }

  /// `yyyyMMdd-HHmm` without pulling in an intl dependency.
  String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}';
  }
}
