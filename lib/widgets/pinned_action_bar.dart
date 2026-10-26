import 'package:flutter/material.dart';

/// Sticky-style bottom action row for review/confirmation flows. Place in a
/// Scaffold.bottomNavigationBar so it remains visible while the body scrolls.
class PinnedActionBar extends StatelessWidget {
  const PinnedActionBar({
    super.key,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.busy = false,
    this.enabled = true,
  });

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool busy;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Row(
        children: [
          if (secondaryLabel != null)
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : onSecondary,
                child: Text(secondaryLabel!),
              ),
            ),
          if (secondaryLabel != null) const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: busy || !enabled ? null : onPrimary,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(primaryLabel),
            ),
          ),
        ],
      ),
    ),
  );
}
