import 'dart:async';

import '../routes/app_router.dart';
import '../routes/app_routes.dart';

/// Opens Today for any reminder tap. The payload identifies the source row,
/// but both class and event reminders land on the schedule the user checks
/// first; resolving a row-specific destination is a separate product change.
typedef RouteOpener = void Function(String route);

void handleNotificationTap(String? payload, {RouteOpener? openRoute}) {
  final open = openRoute ?? _openWithNavigator;
  open(AppRoutes.home);
}

void _openWithNavigator(String route) {
  final navigator = AppRouter.navigatorKey.currentState;
  if (navigator != null) unawaited(navigator.pushNamed(route));
}
