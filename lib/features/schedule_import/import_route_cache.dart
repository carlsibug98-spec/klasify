import 'dart:async';

import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';

/// Keeps an in-progress import route mounted while the user visits Today.
/// Returning to Import reveals the same route and its current widget state.
class ImportRouteCache {
  ImportRouteCache._();

  static Route<dynamic>? _pausedRoute;

  static bool get hasPausedImport => _pausedRoute?.isActive ?? false;

  static void pause(Route<dynamic> route) {
    _pausedRoute = route;
  }

  static void release(Route<dynamic>? route) {
    if (identical(_pausedRoute, route)) _pausedRoute = null;
  }

  static bool resume(NavigatorState navigator) {
    final route = _pausedRoute;
    if (route == null) return false;

    _pausedRoute = null;
    if (!route.isActive) return false;
    navigator.popUntil((candidate) => identical(candidate, route));
    return true;
  }
}

/// Opens a fresh import or returns to the one the user previously paused.
void openOrResumeImport(BuildContext context) {
  final navigator = Navigator.of(context, rootNavigator: true);
  if (ImportRouteCache.resume(navigator)) return;
  unawaited(navigator.pushNamed<void>(AppRoutes.importSchedule));
}
