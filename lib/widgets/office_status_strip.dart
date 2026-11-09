import 'package:flutter/material.dart';

import '../models/office_status.dart';
import '../theme/app_theme.dart';

/// The Today screen's campus-office strip: guidance, clinic and registrar
/// side by side, each carrying its last-known state (open / on break /
/// closed) and the admin's optional note. The values come from the local
/// cache, so the strip keeps showing the last synced state offline.
///
/// Admins get a small edit affordance (✎) on each tile; tapping opens the
/// same bottom sheet as Settings → Admin. Students see the strip as before.
class OfficeStatusStrip extends StatelessWidget {
  const OfficeStatusStrip({
    super.key,
    required this.offices,
    this.isAdmin = false,
    this.onEditOffice,
  });

  final List<OfficeStatus> offices;
  final bool isAdmin;
  final ValueChanged<OfficeStatus>? onEditOffice;

  @override
  Widget build(BuildContext context) {
    if (offices.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final latest = offices
        .map((o) => o.updatedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.pageInset,
        AppTheme.sectionGap,
        AppTheme.pageInset,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    'CAMPUS OFFICES',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontSize: 11,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.3,
                      color: AppTheme.groupLabelColorOf(scheme),
                    ),
                  ),
                ),
                if (latest != null)
                  Text(
                    'Updated ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(latest.toLocal()), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                      height: 1.2,
                      color: AppTheme.placeholderFor(scheme),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.cardFillColorOf(scheme),
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.fromBorderSide(AppTheme.cardBorderSideOf(scheme)),
              boxShadow: AppTheme.cardShadowsOf(scheme),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, office) in offices.indexed) ...[
                      if (index > 0)
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: AppTheme.cardBorderSideOf(scheme).color,
                        ),
                      _OfficeTile(
                        office: office,
                        isAdmin: isAdmin,
                        onTap: isAdmin && onEditOffice != null
                            ? () => onEditOffice!(office)
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (isAdmin)
            Padding(
              padding: const EdgeInsets.only(left: 2, top: 6),
              child: Text(
                'Tap an office to change its status. Students see the change after sync.',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10.5,
                  color: AppTheme.placeholderFor(scheme),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OfficeTile extends StatelessWidget {
  const _OfficeTile({
    required this.office,
    required this.isAdmin,
    this.onTap,
  });

  final OfficeStatus office;
  final bool isAdmin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (background, foreground, dot) = switch (office.status) {
      'open' => (
        AppTheme.successBackgroundOf(context),
        AppTheme.successForegroundOf(context),
        AppTheme.success,
      ),
      'break' => (
        AppTheme.warningBackgroundOf(context),
        AppTheme.warningForegroundOf(context),
        const Color(0xFFB07800),
      ),
      _ => (
        scheme.surfaceContainerHigh,
        scheme.onSurfaceVariant,
        scheme.outline,
      ),
    };

    final tile = Container(
      constraints: const BoxConstraints(minWidth: 110),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  office.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: foreground.withValues(alpha: 0.8),
                  ),
                ),
              ),
              if (isAdmin)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 13,
                    color: foreground.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            office.statusLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
          if (office.message != null && office.message!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              office.message!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10.5,
                height: 1.2,
                color: foreground.withValues(alpha: 0.75),
              ),
            ),
          ] else
            const SizedBox(height: 2),
        ],
      ),
    );

    if (isAdmin && onTap != null) {
      return InkWell(
        onTap: onTap,
        child: tile,
      );
    }
    return tile;
  }
}
