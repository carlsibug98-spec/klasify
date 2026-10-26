import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Compact time field used by class create/edit forms. Keeps the complete
/// control tappable and presents a consistent time-picker affordance.
class TimeBox extends StatelessWidget {
  const TimeBox({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.errorText,
    this.isPlaceholder = false,
    this.hasError = false,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final String? errorText;
  final bool isPlaceholder;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final invalid = hasError || errorText != null;
    final background = invalid
        ? scheme.errorContainer
        : isPlaceholder
        ? scheme.surfaceContainer
        : scheme.surfaceContainerHighest;
    return Semantics(
      button: true,
      label: '$label, $value${invalid ? ', invalid' : ''}',
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.controlRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.controlRadius),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: textTheme.labelMedium?.copyWith(
                            color: invalid
                                ? scheme.error
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          value,
                          style: textTheme.titleLarge?.copyWith(
                            color: invalid
                                ? scheme.error
                                : isPlaceholder
                                ? AppTheme.placeholderFor(scheme)
                                : scheme.onSurface,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (errorText != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            errorText!,
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.access_time_rounded,
                    size: 20,
                    color: invalid ? scheme.error : scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
