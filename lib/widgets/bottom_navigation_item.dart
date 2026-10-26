import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Bottom tab with the 52 × 28 icon pill and an M3-style label beneath it.
///
/// The label is always visible (not just for the selected tab): three
/// destinations must be recognized, not recalled, and the label doubles as
/// the visible name alongside the existing Semantics label.
class BottomNavigationItem extends StatelessWidget {
  const BottomNavigationItem({
    super.key,
    required this.label,
    required this.selected,
    required this.icon,
    required this.onTap,
    this.badge,
    this.showDot = false,
  });

  final String label;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;
  final String? badge;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 56,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 52,
                height: 28,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    AnimatedContainer(
                      duration: AppTheme.motionDuration(
                        context,
                        AppTheme.motionFast,
                      ),
                      curve: AppTheme.motionEaseOut,
                      width: 52,
                      height: 28,
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.primaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(icon, size: 22, color: foreground),
                    ),
                    if (badge != null)
                      Positioned(
                        top: -4,
                        right: -6,
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            // Remaining classes are information, not an
                            // alert: the badge stays monochrome (primary),
                            // distinct from the selected pill's
                            // primaryContainer background.
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            badge!,
                            style: TextStyle(
                              color: scheme.onPrimary,
                              fontSize: 12,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    if (showDot)
                      Positioned(
                        top: 0,
                        right: 4,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              // Excluded from semantics: the outer Semantics(label:) above is
              // the single source of truth for screen readers, so the label
              // is announced once, not twice (explicit label + merged text).
              ExcludeSemantics(
                child: AnimatedDefaultTextStyle(
                  duration: AppTheme.motionDuration(
                    context,
                    AppTheme.motionFast,
                  ),
                  curve: AppTheme.motionEaseOut,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    letterSpacing: 0.2,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: foreground,
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
