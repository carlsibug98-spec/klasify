import 'package:flutter/material.dart';

import '../../services/app_info.dart';
import '../../theme/app_theme.dart';
import 'profile_sheets.dart';

/// Shared pieces for the Profile tab world (mockup v9): the segmented row
/// groups with their tracked caps + description lines, the status pill, the
/// subhead over pushed screens, form fields, and the quiet text links.
/// Every screen of the Profile build reuses these so the visual language
/// stays one thing.

/// A rounded segment Material carrying the approved card edge (hairline +
/// ambient in light, lifted fill in dark) — the building block of every
/// row in this world. Radius logic comes from [AppTheme.segmentRadiusOf].
class ProfileSegment extends StatelessWidget {
  const ProfileSegment({super.key, required this.radius, required this.child});

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

/// A tracked-caps group label, an optional gray description line under it
/// (the "how they utilise spaces" pattern — hub screens only, never the
/// daily Profile tab), and the group's rows as their own segments.
class ProfileGroup extends StatelessWidget {
  const ProfileGroup({
    super.key,
    required this.label,
    this.description,
    required this.rows,
  });

  final String label;

  /// The gray line under the label describing the section's job.
  final String? description;

  /// Full-width row widgets inside the group's segments.
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dimColor = AppTheme.groupLabelColorOf(scheme);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                  color: dimColor,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 4),
                Text(
                  description!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    height: 1.45,
                    color: AppTheme.placeholderFor(scheme),
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: description == null ? 8 : 9),
        for (
          var i = 0;
          i < rows.length;
          i++
        ) ...[
          if (i > 0) const SizedBox(height: AppTheme.segmentGap),
          ProfileSegment(
            radius: AppTheme.segmentRadiusOf(i, rows.length),
            child: rows[i],
          ),
        ],
      ],
    );
  }
}

/// The quiet state pill: the dot carries the colour, the word carries the
/// state. [label] overrides the word when the state needs a different
/// name ("Active" next to a signed-in phone).
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.on, this.label});

  final bool on;
  final String? label;

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
            label ?? (on ? 'On' : 'Off'),
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              height: 1.1,
              fontWeight: FontWeight.w700,
              color: on ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The subhead over a pushed screen (frames 3-8): big heavy title plus the
/// one gray line that says what the screen is for. Sits at the top of the
/// scrolling content, under the small back-row app bar.
class ProfileSubhead extends StatelessWidget {
  const ProfileSubhead({super.key, required this.title, required this.tagline});

  final String title;
  final String tagline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineSmall,
          semanticsLabel: title,
        ),
        const SizedBox(height: 4),
        Text(
          tagline,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 13,
            height: 1.45,
            color: AppTheme.placeholderFor(scheme),
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}

/// An app bar for pushed screens: no big title — the small back-row label
/// naming the screen you came from, exactly like the mockup's back rows.
class ProfileTitleBar extends StatelessWidget implements PreferredSizeWidget {
  const ProfileTitleBar({super.key, required this.parent});

  /// The parent screen's name as the small app bar label.
  final String parent;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppBar(
      automaticallyImplyLeading: true,
      title: Text(
        parent,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
      ),
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
    );
  }
}

/// One row inside a [ProfileGroup]'s segment, to the mock's metrics: 35×35
/// leading tile, 15px title (+ optional 12.5px subtitle), and a trailing
/// slot for the state pill or switch — a chevron appears by itself when the
/// row opens something and nothing else is trailing. Use [footer] for
/// content that wraps to its own line under the title (the lead-time chips).
class ProfileRow extends StatelessWidget {
  const ProfileRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Pill, switch, or anything else that rides the row's end. When null and
  /// the row opens something ([onTap] set), the disclosure chevron shows.
  final Widget? trailing;

  /// Full-width content below the title line (inside the row's padding).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final resolvedTrailing = trailing ??
        (onTap == null
            ? null
            : Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: scheme.outline,
              ));
    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 35,
                    height: 35,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      icon,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 15,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                            color: scheme.onSurface,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12.5,
                              height: 1.2,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (resolvedTrailing != null) ...[
                    const SizedBox(width: 9),
                    resolvedTrailing,
                  ],
                ],
              ),
              if (footer != null) footer!,
            ],
          ),
        ),
      ),
    );
  }
}

/// The mockup's form field: a filled segment with a small tracked label
/// always shown above the input, radius 14, hairline border that darkens
/// on focus (the theme's routed focus outline supplies that).
class ProfileField extends StatelessWidget {
  const ProfileField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.maxLength,
    this.autofillHints,
    this.errorText,
    this.onChanged,
    this.textInputAction,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final int? maxLength;
  final List<String>? autofillHints;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      maxLength: maxLength,
      autofillHints: autofillHints,
      autocorrect: false,
      enableSuggestions: !obscure,
      onChanged: onChanged,
      textInputAction: textInputAction,
      style: TextStyle(
        fontSize: 15.5,
        height: 1.3,
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        hintText: hint,
        counterText: '',
        errorText: errorText,
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        floatingLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// The two quiet text links of the mockup: the left-aligned "Forgot your
/// password?" card link ([danger] false, the signed-in password page uses
/// it) and the centered red danger link ("Delete account…").
class ProfileLink extends StatelessWidget {
  const ProfileLink({
    super.key,
    required this.text,
    required this.onTap,
    this.danger = false,
    this.center = false,
    this.icon,
  });

  final String text;
  final VoidCallback? onTap;

  /// Red text (with a red icon when given) — "Delete account…".
  final bool danger;

  /// Centered instead of the left-aligned quiet link.
  final bool center;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = danger ? scheme.error : scheme.onSurfaceVariant;
    final button = icon == null
        ? TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: color,
              textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
              alignment: center ? Alignment.center : Alignment.centerLeft,
            ),
            child: Text(text),
          )
        : TextButton.icon(
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: color,
              textStyle: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            icon: Icon(icon, size: 16, color: color),
            label: Text(text),
          );
    return SizedBox(width: double.infinity, child: button);
  }
}

/// The 48×28 switch sized exactly as the approved toggle (Material's 52×32
/// Switch would push rows taller than the mock); the 48×48 hit area rides
/// around the visual, supplying keyboard and focus semantics as well.
class MiniSwitch extends StatelessWidget {
  const MiniSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticsLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    final duration = AppTheme.motionDuration(context, AppTheme.motionToggle);
    final trackColor = value ? scheme.primary : scheme.surfaceContainerHighest;
    final knobColor = value ? scheme.onPrimary : scheme.surface;
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticsLabel,
      onTap: enabled ? () => onChanged!(!value) : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? () => onChanged!(!value) : null,
          excludeFromSemantics: true,
          customBorder: const StadiumBorder(),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          focusColor: scheme.primary.withValues(alpha: 0.12),
          hoverColor: scheme.primary.withValues(alpha: 0.08),
          child: Opacity(
            opacity: enabled ? 1 : 0.55,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 48,
                  height: 28,
                  child: AnimatedContainer(
                    duration: duration,
                    curve: AppTheme.motionEaseOut,
                    decoration: BoxDecoration(
                      color: trackColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: AnimatedAlign(
                      duration: duration,
                      curve: AppTheme.motionEaseOut,
                      alignment: value
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: knobColor,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox.square(dimension: 22),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The version line under the last group ("Klasify 1.4.4 (build 15)").
/// Tapping it opens the About sheet, keeping licenses reachable now that
/// the hub's ABOUT group lives no more.
class ProfileVersionLine extends StatelessWidget {
  const ProfileVersionLine({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: TextButton(
        onPressed: () => showProfileAboutSheet(context),
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.placeholderFor(scheme),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        child: Text('Klasify ${AppInfo.version} (build ${AppInfo.build})'),
      ),
    );
  }
}
