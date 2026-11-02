import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'live_pulse.dart';
import 'pressable_scale.dart';

/// The hero block at the top of Today — a segment stack on the tier system.
///
/// The states mirror the Android widget, minus its LATER TODAY rows: those
/// live only on the widget, because the Today list right below this card
/// already shows the day's remaining classes.
///   * live now — pulse dot, tracked-caps status, room CTA, subject, "ENDS
///     IN" caption, big countdown, 6px gradient bar;
///   * next up — the same hero on the raised tier, "STARTS IN" caption, a
///     day pill when the class is on another day;
///   * all done / free day / weekend — an outline check row; with a next
///     class ahead it becomes the top segment of a two-segment stack whose
///     bottom segment is the next-class shelf;
///   * empty schedule — logo mark, "No classes scheduled".
///
/// Geometry is [AppTheme.segmentRadiusOf] verbatim (16px outer corners, 2px
/// meeting edges) with [AppTheme.segmentGap] seams of scaffold between
/// segments. Colour is decided by meaning, not position: a class you can
/// still catch sits on the raised isNext tier, celebrations and the empty
/// state sit on the quiet card tier. Countdowns read "24 min" — the caption
/// above already carries the direction, so no "left" suffix anywhere.
class NextClassCard extends StatelessWidget {
  final String label;
  final String subject;
  final String room;

  /// Celebration shelf only: the next class's time range under its subject.
  /// Class states have no time line; the countdown carries that job.
  final String time;

  /// Right side of the live row. The next-up state uses the big [countdown]
  /// instead, and the shelf uses this as the starts-in line.
  final String whenText;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? celebrationTitle;
  final String? celebrationSubtitle;
  final IconData? celebrationIcon;

  /// Day pill in the hero header ("TOMORROW", "MONDAY") when the next class
  /// is on another day, and on the celebration shelf.
  final String? dayPillText;

  /// Time left in the live class, or time until the next-up class. The card
  /// turns this into structured big-number/small-unit type.
  final Duration? countdown;

  /// For the "In class" hero: elapsed fraction (0..1), drawn as a 6px rounded
  /// gradient bar inside the hero. Null = no bar.
  final double? liveProgress;

  /// Minutes left in the live class: the bar tween duration, so it moves at
  /// exactly real-time speed instead of a cosmetic fixed duration.
  final Duration? liveRemaining;

  /// Celebration only: makes the "next class" shelf tappable (e.g. jump to
  /// that day on the Week tab). Null keeps the shelf inert.
  final VoidCallback? onTeaserTap;

  final bool _empty;

  const NextClassCard({
    super.key,
    required this.label,
    required this.subject,
    this.room = '',
    this.time = '',
    this.whenText = '',
    this.onTap,
    this.onLongPress,
    this.celebrationTitle,
    this.celebrationSubtitle,
    this.celebrationIcon,
    this.dayPillText,
    this.countdown,
    this.liveProgress,
    this.liveRemaining,
    this.onTeaserTap,
  }) : _empty = false;

  /// Celebration only ("Good job"). Shows no class details unless a teaser
  /// (the next upcoming class) is passed.
  const NextClassCard.celebration({
    super.key,
    required String title,
    required String subtitle,
    required IconData icon,
    this.onTeaserTap,
    this.dayPillText,
    this.whenText = '',
    this.subject = '',
    this.time = '',
    this.room = '',
  }) : label = '',
       countdown = null,
       onTap = null,
       onLongPress = null,
       celebrationTitle = title,
       celebrationSubtitle = subtitle,
       celebrationIcon = icon,
       liveProgress = null,
       liveRemaining = null,
       _empty = false;

  const NextClassCard.empty({super.key})
    : label = 'No classes scheduled',
      subject = 'Add a class or import a timetable to begin.',
      room = '',
      time = '',
      whenText = '',
      onTap = null,
      onLongPress = null,
      celebrationTitle = null,
      celebrationSubtitle = null,
      celebrationIcon = null,
      dayPillText = null,
      countdown = null,
      liveProgress = null,
      liveRemaining = null,
      onTeaserTap = null,
      _empty = true;

  bool get _isLive => label == 'Live now' || label == 'In class';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final isCelebration =
        celebrationTitle != null || celebrationSubtitle != null;

    // The raised tier marks a class you can still catch; everything else
    // sits on the quiet card tier.
    final heroFill = AppTheme.cardFillColorOf(scheme, isNext: true);
    final quietFill = AppTheme.cardFillColorOf(scheme);

    final List<Widget> segments;
    if (_empty) {
      segments = [
        _Segment(
          fill: quietFill,
          radius: AppTheme.segmentRadiusOf(0, 1),
          child: const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 18, 16),
            child: _EmptyBody(),
          ),
        ),
      ];
    } else if (isCelebration) {
      // Solo celebration rounds fully; with a shelf below it becomes the
      // first segment of two (16px top, 2px meeting bottom).
      final checkRadius =
          _hasUpNext
          ? AppTheme.segmentRadiusOf(0, 2)
          : AppTheme.segmentRadiusOf(0, 1);
      segments = [
        // Top segment: the check row. Bottom segment (only when a next
        // class exists): the shelf, flat on its own segment — the 1px seam
        // of scaffold replaces the old inset box.
        _Segment(
          fill: quietFill,
          radius: checkRadius,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 17, 18, 17),
            child: _CheckRow(
              title: celebrationTitle ?? label,
              subtitle: celebrationSubtitle ?? subject,
              icon: celebrationIcon,
              textTheme: textTheme,
            ),
          ),
        ),
        if (_hasUpNext) ...[
          const SizedBox(height: AppTheme.segmentGap),
          _Segment(
            fill: quietFill,
            radius: AppTheme.segmentRadiusOf(1, 2),
            onTap: onTeaserTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 13, 18, 16),
              child: _ShelfBody(
                dayPillText: dayPillText,
                whenText: whenText,
                subject: subject,
                time: time,
                textTheme: textTheme,
              ),
            ),
          ),
        ],
      ];
    } else {
      segments = [
        _Segment(
          fill: heroFill,
          radius: AppTheme.segmentRadiusOf(0, 1),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 17, 18, 18),
            child: _ClassBody(
              label: label,
              dayPillText: dayPillText,
              subject: subject.trim(),
              room: room.trim(),
              countdown: countdown,
              isLive: _isLive,
              liveProgress: liveProgress,
              liveRemaining: liveRemaining,
              textTheme: textTheme,
            ),
          ),
        ),
      ];
    }

    // One segment renders alone; two or more stack with scaffold seams.
    Widget content = segments.first;
    for (final (index, segment) in segments.indexed) {
      if (index == 0) continue;
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [content, const SizedBox(height: AppTheme.segmentGap), segment],
      );
    }

    return SizedBox(
      width: double.infinity,
      child: Semantics(
        container: true,
        button: onTap != null,
        label:
            [
                  if (celebrationTitle != null) celebrationTitle!,
                  if (celebrationSubtitle != null) celebrationSubtitle!,
                  if (dayPillText != null) dayPillText!,
                  label,
                  subject,
                  time,
                  room,
                  if (_isLive && whenText.isNotEmpty) whenText,
                  if (!_isLive && countdown != null)
                    whenText.isNotEmpty
                        ? whenText
                        : 'Starts in ${_countdownSummary(countdown!)}',
                  if (isCelebration && whenText.isNotEmpty) whenText,
                ]
                .whereType<String>()
                .where((value) => value.trim().isNotEmpty)
                .join('. '),
        child: PressableScale(
          enabled: onTap != null,
          child: content,
        ),
      ),
    );
  }

  /// The shelf only appears when there is an upcoming class to show. Without
  /// one, the celebration stays a single quiet segment instead of leaving an
  /// empty block.
  bool get _hasUpNext =>
      (dayPillText?.trim().isNotEmpty ?? false) ||
      whenText.trim().isNotEmpty ||
      subject.trim().isNotEmpty;
}

/// One segment of the stack: themed fill, hairline edge, the card's ambient
/// shadow in light mode, and its own tap target (the hero swipes/deletes,
/// the shelf jumps to the week view).
class _Segment extends StatelessWidget {
  const _Segment({
    required this.fill,
    required this.radius,
    required this.child,
    this.onTap,
    this.onLongPress,
  });

  final Color fill;
  final BorderRadius radius;
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: AppTheme.cardShadowsOf(scheme),
      ),
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: AppTheme.cardBorderSideOf(scheme),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: child,
        ),
      ),
    );
  }
}

/// The class hero: status row (day pill, tracked caps, room CTA), subject,
/// structured countdown, and the live progress bar.
class _ClassBody extends StatelessWidget {
  const _ClassBody({
    required this.label,
    required this.dayPillText,
    required this.subject,
    required this.room,
    required this.countdown,
    required this.isLive,
    required this.liveProgress,
    required this.liveRemaining,
    required this.textTheme,
  });

  final String label;
  final String? dayPillText;
  final String subject;
  final String room;
  final Duration? countdown;
  final bool isLive;
  final double? liveProgress;
  final Duration? liveRemaining;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showRoomCta = room.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (isLive) ...[
              LivePulse(
                size: 8,
                color: AppTheme.liveOf(context),
                haloOpacity: 0.22,
              ),
              const SizedBox(width: 9),
            ],
            if (dayPillText != null && dayPillText!.trim().isNotEmpty) ...[
              _DayPill(text: dayPillText!.trim(), textTheme: textTheme),
              const SizedBox(width: 9),
            ],
            // Tracked-caps status line. Orange is reserved for the live
            // state; next up stays label-grey.
            _CapsLabel(
              text: label,
              color: isLive ? AppTheme.liveOf(context) : null,
              textTheme: textTheme,
            ),
            const Spacer(),
            // The room is the second thing you look for after the class
            // name, so it stays on the status line in both states. Live used
            // to put "Ends in 24m" here; the big countdown carries that now.
            if (showRoomCta)
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _RoomCta(room: room, textTheme: textTheme),
                ),
              ),
          ],
        ),
        const SizedBox(height: 13),
        Text(
          subject,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleLarge?.copyWith(
            color: scheme.onSurface,
            fontSize: 20,
            height: 1.25,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        if (countdown != null) ...[
          const SizedBox(height: 11),
          // Without this caption the big numbers read like the class's
          // duration. The direction lives here; the units stay bare.
          Text(
            isLive ? 'ENDS IN' : 'STARTS IN',
            style: textTheme.labelSmall?.copyWith(
              color: AppTheme.groupLabelColorOf(scheme),
              fontSize: 10.5,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          _HeroCountdown(duration: countdown!, textTheme: textTheme),
        ],
        if (isLive && liveProgress != null) ...[
          const SizedBox(height: 16),
          _LiveProgressBar(progress: liveProgress!, remaining: liveRemaining),
        ],
      ],
    );
  }
}

/// Tracked small caps: 11px, +1.1 tracking, uppercase. Label-grey unless a
/// [color] overrides it (the live state).
class _CapsLabel extends StatelessWidget {
  const _CapsLabel({
    required this.text,
    required this.textTheme,
    this.color,
  });

  final String text;
  final TextTheme textTheme;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      // Tracked caps render uppercase, matching the widget's textAllCaps.
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textTheme.labelSmall?.copyWith(
        color: color ?? AppTheme.groupLabelColorOf(scheme),
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
  }
}

/// Day pill ("TOMORROW"): the inverted pill marking a class on another day.
class _DayPill extends StatelessWidget {
  const _DayPill({required this.text, required this.textTheme});

  final String text;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: textTheme.labelSmall?.copyWith(
          color: scheme.onPrimary,
          fontSize: 10,
          height: 1.1,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Room CTA in the top-right: the one inverted pill on the tier surface.
class _RoomCta extends StatelessWidget {
  const _RoomCta({required this.room, required this.textTheme});

  final String room;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: false,
      label: 'Room $room',
      excludeSemantics: true,
      child: Container(
        height: 30,
        padding: const EdgeInsets.only(left: 10, right: 13),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _NavArrow(size: 15),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                room,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onPrimary,
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Big structured countdown: 42px values with 15px units on the baseline.
/// Units stay bare ("1 h 25 min", "24 min") — the caption above carries the
/// direction, so nothing says "left".
class _HeroCountdown extends StatelessWidget {
  const _HeroCountdown({required this.duration, required this.textTheme});

  final Duration duration;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parts = _countdownParts(duration);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        for (final (index, part) in parts.indexed) ...[
          if (index > 0) const SizedBox(width: 10),
          Text(
            part.value,
            style: textTheme.displaySmall?.copyWith(
              color: scheme.onSurface,
              fontSize: 42,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 4),
          Text(
            part.unit,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 15,
              height: 1.2,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ],
      ],
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: row,
      ),
    );
  }
}

/// The 6px in-hero elapsed bar: rounded track, orange gradient fill.
///
/// One linear tween from the current fraction to full over exactly the
/// minutes the class has left, so the bar's speed IS the class's speed —
/// the hero rebuilds each minute and the tween retargets without jumping.
/// Reduced motion: a static bar at the current fraction, no animation.
class _LiveProgressBar extends StatelessWidget {
  const _LiveProgressBar({required this.progress, this.remaining});

  /// 0..1 elapsed fraction at build time.
  final double progress;

  /// Time left in the class. Null (or non-positive) renders a static bar.
  final Duration? remaining;

  @override
  Widget build(BuildContext context) {
    Widget bar(double fraction) {
      final f = fraction.clamp(0.0, 1.0);
      return ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Container(
          height: 6,
          color: Theme.of(context).colorScheme.outlineVariant,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: f,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.liveOf(context),
                    AppTheme.liveSoftOf(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final effectiveRemaining = remaining;
    if (effectiveRemaining == null ||
        effectiveRemaining <= Duration.zero ||
        MediaQuery.of(context).disableAnimations) {
      return bar(progress);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: progress.clamp(0.0, 1.0), end: 1),
      duration: effectiveRemaining,
      curve: Curves.linear,
      builder: (context, value, _) => bar(value),
    );
  }
}

/// The celebration check row: outline icon, heavy title, quiet subtitle.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.textTheme,
  });

  final String title;
  final String subtitle;
  final IconData? icon;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          ExcludeSemantics(
            child: Icon(icon, size: 26, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 13),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  color: scheme.onSurface,
                  fontSize: 19,
                  height: 1.26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                ),
              ),
              if (subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The next-class shelf, flat on its own quiet segment: day pill left,
/// starts-in right, then the subject and its time range.
class _ShelfBody extends StatelessWidget {
  const _ShelfBody({
    required this.dayPillText,
    required this.whenText,
    required this.subject,
    required this.time,
    required this.textTheme,
  });

  final String? dayPillText;
  final String whenText;
  final String subject;
  final String time;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (dayPillText != null && dayPillText!.isNotEmpty)
              _DayPill(text: dayPillText!, textTheme: textTheme),
            if (whenText.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  whenText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 9),
        Text(
          subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodyMedium?.copyWith(
            color: scheme.onSurface,
            fontSize: 15,
            height: 1.3,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.1,
          ),
        ),
        if (time.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.access_time_rounded,
                size: 13,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  time.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w400,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Empty-schedule state: logo tile plus copy, on one quiet segment.
class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(13),
          ),
          child: _LogoMark(color: scheme.onPrimary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No classes scheduled',
                style: textTheme.titleMedium?.copyWith(
                  color: scheme.onSurface,
                  fontSize: 17,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Add a class or import a timetable to begin.',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.3,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The three-bar Klasify mark used by the empty state. The bars take the
/// tile's inverse colour so the mark survives both tile fills; the dot
/// stays the signal orange.
class _LogoMark extends StatelessWidget {
  const _LogoMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _LogoMarkPainter(color: color));
}

class _LogoMarkPainter extends CustomPainter {
  const _LogoMarkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 40;
    final bars = Paint()..color = color;
    final orange = Paint()..color = const Color(0xFFFF8A5C);
    if (size.width < size.height) {
      canvas.translate(0, (size.height - size.width) / 2);
    }
    final unit = 40.0 * scale;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          9 * unit / 40,
          9 * unit / 40,
          24 * unit / 40,
          4 * unit / 40,
        ),
        Radius.circular(2 * unit / 40),
      ),
      bars,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          9 * unit / 40,
          16 * unit / 40,
          24 * unit / 40,
          4 * unit / 40,
        ),
        Radius.circular(2 * unit / 40),
      ),
      bars,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          9 * unit / 40,
          23 * unit / 40,
          14 * unit / 40,
          4 * unit / 40,
        ),
        Radius.circular(2 * unit / 40),
      ),
      bars,
    );
    canvas.drawCircle(
      Offset(4 * unit / 40, 11 * unit / 40),
      2 * unit / 40,
      orange,
    );
  }

  @override
  bool shouldRepaint(covariant _LogoMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The mock's room affordance: a stroked navigation arrow on a 24-unit grid,
/// drawn as a path so it matches the design instead of a filled font glyph.
class _NavArrow extends StatelessWidget {
  const _NavArrow({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _NavArrowPainter()),
  );
}

class _NavArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final path = Path()
      ..moveTo(3 * s, 3 * s)
      ..lineTo(10.07 * s, 19.97 * s)
      ..lineTo(12.58 * s, 12.58 * s)
      ..lineTo(19.97 * s, 10.07 * s)
      ..close();
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF000000)
      ..isAntiAlias = true;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _NavArrowPainter oldDelegate) => false;
}

/// [Duration] -> the two biggest value/unit pairs, e.g. "1h 25min" or
/// "2d 3h". Units stay bare — "24 min", "1 h 30 min"; the "STARTS IN" /
/// "ENDS IN" caption above the numbers carries the direction.
List<({String value, String unit})> _countdownParts(Duration duration) {
  final totalMinutes = duration.inMinutes.clamp(0, 7 * 24 * 60);
  if (totalMinutes >= 1440) {
    final days = totalMinutes ~/ 1440;
    final hours = (totalMinutes % 1440) ~/ 60;
    return [
      (value: '$days', unit: 'd'),
      if (hours > 0) (value: '$hours', unit: 'h'),
    ];
  }
  if (totalMinutes >= 60) {
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return [
      (value: '$hours', unit: 'h'),
      if (minutes > 0) (value: '$minutes', unit: 'min'),
    ];
  }
  return [(value: '${totalMinutes == 0 ? 1 : totalMinutes}', unit: 'min')];
}

String _countdownSummary(Duration duration) {
  final parts = _countdownParts(duration);
  return parts.map((part) => '${part.value}${part.unit}').join(' ');
}
