import 'package:flutter/material.dart';

import '../models/office_status.dart';
import '../theme/app_theme.dart';

/// The Today screen's campus-office strip (design C): one card, a column
/// per office — a 4px status bar over the name, the state ("Open" / "On
/// break" / "Closed") and the admin's optional note. Three columns share
/// the width; a fourth or later scrolls sideways. Values come from the
/// local cache, so the strip keeps showing the last synced state offline.
///
/// Admins get a 24px edit chip (✎) on each column; tapping opens the same
/// bottom sheet as Settings → Admin. An office whose change is still
/// syncing shows "Syncing…" in place of its note; one whose PATCH is in
/// flight is dimmed.
class OfficeStatusStrip extends StatelessWidget {
  const OfficeStatusStrip({
    super.key,
    required this.offices,
    this.isAdmin = false,
    this.pendingOffices = const {},
    this.savingOffice,
    this.onEditOffice,
  });

  final List<OfficeStatus> offices;

  /// Show edit chips and make the columns tappable.
  final bool isAdmin;

  /// Offices whose change saved on the server but has not finished syncing
  /// to this phone yet; their sub line reads "Syncing…".
  final Set<String> pendingOffices;

  /// The office whose PATCH is currently in flight; its column dims.
  final String? savingOffice;

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

    final hintBits = <String>[
      if (isAdmin) 'Tap an office to change it. Students see the change after sync.',
      if (offices.length > 3) 'Swipe sideways to see all offices.',
    ];

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
          // Three columns share the card's width; more offices keep that
          // third-width and scroll horizontally (mockup: minmax(33.33%, 1fr)).
          LayoutBuilder(
            builder: (context, constraints) {
              final tileWidth = (constraints.maxWidth / 3).clamp(110.0, double.infinity);
              return Container(
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
                          SizedBox(
                            width: tileWidth,
                            child: _OfficeTile(
                              office: office,
                              isAdmin: isAdmin,
                              pending: pendingOffices.contains(office.office),
                              saving: savingOffice == office.office,
                              onTap:
                                  isAdmin && onEditOffice != null
                                  ? () => onEditOffice!(office)
                                  : null,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          if (hintBits.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 2, top: 6),
              child: Text(
                hintBits.join(' '),
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
    required this.pending,
    required this.saving,
    this.onTap,
  });

  final OfficeStatus office;
  final bool isAdmin;
  final bool pending;
  final bool saving;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (foreground, bar) = switch (office.status) {
      'open' => (AppTheme.successForegroundOf(context), AppTheme.success),
      'break' => (
        AppTheme.warningForegroundOf(context),
        const Color(0xFFB07800),
      ),
      _ => (scheme.onSurfaceVariant, scheme.outline.withValues(alpha: 0.5)),
    };

    final tile = Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Fixed 24px top row in both views, so student and admin columns
          // are the same height: the status bar sits on its centre line,
          // level with the edit chip. The tile's width is fixed by the
          // strip (a third of the card), so the Expanded bar here is safe.
          SizedBox(
            height: 24,
            child: Row(
              children: [
                Expanded(
                  child: Center(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: bar,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                if (isAdmin) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.fromBorderSide(
                        AppTheme.cardBorderSideOf(scheme),
                      ),
                    ),
                    child: Icon(
                      Icons.edit_outlined,
                      size: 13,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            office.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 12,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            office.statusLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 16,
              height: 1.2,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: foreground,
            ),
          ),
          // Fixed-height sub line keeps every column the same height whether
          // or not there is a note; pending replaces the note with "Syncing…".
          SizedBox(
            height: 13,
            child: Align(
              alignment: Alignment.centerLeft,
              child: pending
                  ? Text(
                      'Syncing…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.liveOf(context),
                      ),
                    )
                  : (office.message != null && office.message!.isNotEmpty)
                  ? Text(
                      office.message!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        height: 1.2,
                        color: AppTheme.placeholderFor(scheme),
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );

    final dimmed = saving ? Opacity(opacity: 0.55, child: tile) : tile;
    if (isAdmin && onTap != null) {
      return InkWell(onTap: onTap, child: dimmed);
    }
    return dimmed;
  }
}
