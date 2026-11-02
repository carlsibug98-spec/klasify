import 'package:flutter/material.dart';

import '../routes/app_routes.dart';
import '../services/app_info.dart';
import '../services/reminder_service.dart';
import '../theme/app_theme.dart';
import '../widgets/component_kit.dart';

/// Settings: one calm surface per task.
///
/// Rows render as their own segments — the first row carries the group's top
/// corners, middle rows soften to 2px, the last row carries the bottom
/// corners — separated by a tight 1px seam of scaffold (the approved
/// segmented-rows study). Rows use a neutral leading tile instead of accent
/// decoration, so the only colour on the page belongs to state — the
/// reminders dot.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onReplayCoachTour});

  /// The one-time coach tour lives in the shell; Settings only asks for a
  /// replay across this callback. Null keeps the row inert (tests).
  final VoidCallback? onReplayCoachTour;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Narrower than the schedule surfaces: settings read as a column, not a grid.
  static const double _contentMaxWidth = 680;

  bool? _remindersEnabled;

  @override
  void initState() {
    super.initState();
    ReminderService.instance.addListener(_onReminderSettingsChanged);
    _loadReminderState();
  }

  @override
  void dispose() {
    ReminderService.instance.removeListener(_onReminderSettingsChanged);
    super.dispose();
  }

  void _onReminderSettingsChanged() => _loadReminderState();

  Future<void> _loadReminderState() async {
    final enabled = await ReminderService.instance.isEnabled;
    if (!mounted || enabled == _remindersEnabled) return;
    setState(() => _remindersEnabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text('Settings'),
          ),
          body: ListView(
            padding: AppTheme.pagePadding,
            children: [
              const _SettingsGroup(
                title: 'SCHEDULE',
                rows: [
                  _SettingsRowData(
                    icon: Icons.document_scanner_outlined,
                    title: 'Import schedule',
                    subtitle: 'From a photo or PDF',
                    route: AppRoutes.importSchedule,
                  ),
                  _SettingsRowData(
                    icon: Icons.settings_backup_restore_rounded,
                    title: 'Backup and restore',
                    subtitle: 'Saves automatically after every change',
                    route: AppRoutes.backup,
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.sectionGap),
              _SettingsGroup(
                title: 'NOTIFICATIONS',
                rows: [
                  _SettingsRowData(
                    icon: Icons.notifications_none_rounded,
                    title: 'Class reminders',
                    subtitle: switch (_remindersEnabled) {
                      null => 'Checking status…',
                      true => 'Alerts before each class',
                      false => 'No alerts scheduled',
                    },
                    status: _remindersEnabled,
                    route: AppRoutes.reminders,
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.sectionGap),
              _SettingsGroup(
                title: 'HELP',
                onReplayCoachTour: widget.onReplayCoachTour,
                rows: const [
                  _SettingsRowData(
                    icon: Icons.menu_book_outlined,
                    title: 'How Klasify works',
                    subtitle: 'A quick tour of the basics',
                    route: AppRoutes.onboarding,
                    arguments: true,
                  ),
                  _SettingsRowData(
                    icon: Icons.tour_outlined,
                    title: 'Replay the coach tour',
                    subtitle: 'The guided walkthrough of every screen',
                    action: _SettingsRowAction.coachTour,
                  ),
                  _SettingsRowData(
                    icon: Icons.widgets_outlined,
                    title: 'Home-screen widget',
                    subtitle: 'Your next class at a glance',
                    action: _SettingsRowAction.widgetHelp,
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.sectionGap),
              const _SettingsGroup(
                title: 'ABOUT',
                rows: [
                  _SettingsRowData(
                    icon: Icons.info_outline_rounded,
                    title: 'About Klasify',
                    subtitle: AppInfo.versionLabel,
                    action: _SettingsRowAction.about,
                  ),
                ],
              ),
              const _PrivacyFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SettingsRowAction { route, about, widgetHelp, coachTour }

class _SettingsRowData {
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final Object? arguments;

  /// Reminder state shown as an On/Off pill; null keeps the row neutral.
  final bool? status;
  final _SettingsRowAction action;

  const _SettingsRowData({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.route = '',
    this.arguments,
    this.status,
    this.action = _SettingsRowAction.route,
  });
}

/// A labelled group of row segments. Each row is its own segment with a
/// position-dependent radius (see [AppTheme.segmentRadiusOf]); segments sit
/// [AppTheme.segmentGap] apart with no divider lines.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.title,
    required this.rows,
    this.onReplayCoachTour,
  });

  final String title;
  final List<_SettingsRowData> rows;

  /// Fired by the coach-tour row; null (tests) counts taps, does nothing.
  final VoidCallback? onReplayCoachTour;

  /// The state label (when set) followed by the disclosure chevron.
  Widget _rowTrailing(BuildContext context, _SettingsRowData row) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (row.status != null) ...[
          _StatusPill(on: row.status!),
          const SizedBox(width: 8),
        ],
        Icon(Icons.chevron_right_rounded, size: 20, color: scheme.outline),
      ],
    );
  }

  void _openRow(BuildContext context, _SettingsRowData row) {
    switch (row.action) {
      case _SettingsRowAction.about:
        _showAboutSheet(context);
      case _SettingsRowAction.widgetHelp:
        _showWidgetHelpSheet(context);
      case _SettingsRowAction.coachTour:
        onReplayCoachTour?.call();
      case _SettingsRowAction.route:
        Navigator.pushNamed(context, row.route, arguments: row.arguments);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              fontSize: 11,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
              color: AppTheme.groupLabelColorOf(scheme),
            ),
          ),
        ),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: AppTheme.segmentGap),
          _SettingsSegment(
            radius: AppTheme.segmentRadiusOf(i, rows.length),
            child: SettingsRow(
              compact: true,
              icon: rows[i].icon,
              title: rows[i].title,
              subtitle: rows[i].subtitle,
              trailing: _rowTrailing(context, rows[i]),
              onTap: () => _openRow(context, rows[i]),
            ),
          ),
        ],
      ],
    );
  }
}

/// One settings row as its own segment — the approved segmented-rows study.
///
/// The ambient shadow wraps the Material (it paints behind the segment and
/// must not be clipped); the hairline rides on the Material's shape so it
/// follows the segment's radius. Same edge language as the class cards.
class _SettingsSegment extends StatelessWidget {
  const _SettingsSegment({required this.radius, required this.child});

  final BorderRadius radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: AppTheme.cardShadowsOf(scheme),
      ),
      child: Material(
        color: AppTheme.cardFillColorOf(scheme),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: AppTheme.cardBorderSideOf(scheme),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

/// A quiet state pill: a dot carries the colour, the word carries the state.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: on
                  ? AppTheme.successForegroundFor(scheme)
                  : scheme.outline,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            on ? 'On' : 'Off',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              height: 1.1,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The one identity note on the page: the app keeps the schedule on-device.
class _PrivacyFooter extends StatelessWidget {
  const _PrivacyFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 14,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              AppInfo.tagline,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showAboutSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.sheetRadius),
      ),
    ),
    builder: (_) => const _AboutSheet(),
  );
}

Future<void> _showWidgetHelpSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.sheetRadius),
      ),
    ),
    builder: (_) => const _WidgetHelpSheet(),
  );
}

/// The About bottom sheet: the app's identity, version, and its defining
/// fact, with the licenses one tap away. Same layout idiom as the day
/// status sheet (icon block + title + subtitle on a single quiet surface).
class _AboutSheet extends StatelessWidget {
  const _AboutSheet();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.pageInset,
              6,
              AppTheme.pageInset,
              24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                       decoration: BoxDecoration(
                         color: scheme.surfaceContainer,
                         borderRadius: BorderRadius.circular(14),
                         border: Border.all(color: scheme.outlineVariant),
                       ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/klasify_logo.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: AppTheme.itemGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppInfo.name,
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppInfo.versionLabel,
                            style: textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  AppInfo.tagline,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Timetable, reminders, and the home-screen widget all work '
                  'offline. Automatic backups and file exports move your '
                  'schedule to a new phone.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Divider(color: scheme.outlineVariant),
                InkWell(
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: AppInfo.name,
                    applicationVersion: '${AppInfo.version} (${AppInfo.build})',
                    applicationIcon: const ImageIcon(
                      AssetImage('assets/klasify_logo.png'),
                      size: 44,
                    ),
                    applicationLegalese: AppInfo.tagline,
                  ),
                  borderRadius: BorderRadius.circular(AppTheme.controlRadius),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Open-source licenses',
                            style: textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How to place the native home-screen widget. Widgets live in the launcher,
/// not inside the app, so the steps name the launcher's own vocabulary.
class _WidgetHelpSheet extends StatelessWidget {
  const _WidgetHelpSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.pageInset,
              6,
              AppTheme.pageInset,
              24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.widgets_outlined,
                        size: 22,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: AppTheme.itemGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Home-screen widget',
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Your next class at a glance',
                            style: textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const _WidgetPreview(),
                const SizedBox(height: 20),
                Text(
                  'Add it from your home screen',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                const _WidgetStep(
                  number: 1,
                  text: 'Touch and hold an empty spot on your home screen.',
                ),
                const _WidgetStep(
                  number: 2,
                  text: 'Choose Widgets, then find Klasify.',
                ),
                const _WidgetStep(
                  number: 3,
                  text: 'Drag “Upcoming” to the spot you want.',
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.offline_bolt_outlined,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'The widget updates on its own and works offline.',
                        style: textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A static miniature of the widget, using the app's own surfaces so the
/// sheet stays in the same visual world in light and dark.
class _WidgetPreview extends StatelessWidget {
  const _WidgetPreview();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: const BoxDecoration(
                  color: Color(0xFF262626),
                  borderRadius: BorderRadius.all(Radius.circular(11)),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Next up',
                  style: textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFF2F2F2),
                  ),
                ),
              ),
              const Spacer(),
              Container(
                height: 26,
                padding: const EdgeInsets.only(left: 8, right: 10),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.all(Radius.circular(13)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.navigation_rounded,
                      size: 12,
                      color: Color(0xFF000000),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Lab 2',
                      style: textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF000000),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Data Structures',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleSmall?.copyWith(
              fontSize: 15,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'STARTS IN',
            style: textTheme.labelSmall?.copyWith(
              fontSize: 9,
              height: 1.1,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.9,
              color: const Color(0xFF9A9A9A),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '9',
                style: textTheme.titleLarge?.copyWith(
                  fontSize: 24,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 2),
              Text(
                'h',
                style: textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  height: 1.1,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF8E8E8E),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '48',
                style: textTheme.titleLarge?.copyWith(
                  fontSize: 24,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 2),
              Text(
                'min',
                style: textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  height: 1.1,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF8E8E8E),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WidgetStep extends StatelessWidget {
  const _WidgetStep({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 11,
                height: 1.1,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
