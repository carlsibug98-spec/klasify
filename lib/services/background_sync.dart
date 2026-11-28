import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'auth_service.dart';
import 'app_logger.dart';
import 'local_scope_service.dart';
import 'sync_service.dart';

/// WorkManager task name for the periodic sync.
const String backgroundSyncTask = 'klasifyPeriodicSync';

/// Periodic sync that survives Android killing the app. The foreground
/// 5-minute timer remains for freshness; both paths call the same facade.
class BackgroundSync {
  BackgroundSync._();

  /// Test seam; production uses the real sync facade.
  static Future<bool> Function()? runnerOverride;

  static Future<bool> run() async {
    final runner = runnerOverride ?? () => SyncService.instance.syncNow();
    return runner();
  }

  /// Registers the job on supported platforms. Never throws into launch.
  static Future<void> register() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await Workmanager().initialize(callbackDispatcher);
      await Workmanager().registerPeriodicTask(
        backgroundSyncTask,
        backgroundSyncTask,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (error) {
      AppLogger.e('background', 'Registration failed', error: error);
    }
  }

  /// Restores the signed-in scope in the callback isolate before syncing.
  static Future<void> bootstrap() async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await AuthService.instance.restoreSession();
      await LocalScopeService.instance.initialise();
      final id = AuthService.instance.currentUser?['id'];
      await LocalScopeService.instance.ensureForUser(id is int ? id : null);
    } catch (error) {
      AppLogger.e('background', 'Bootstrap failed', error: error);
    }
  }
}

/// Entry point invoked by WorkManager in its own isolate.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != backgroundSyncTask) return true;
    await BackgroundSync.bootstrap();
    try {
      return await BackgroundSync.run();
    } catch (error) {
      AppLogger.e('background', 'Sync failed', error: error);
      return false;
    }
  });
}

