import 'package:flutter/material.dart';

import 'live_pulse.dart';
import 'pressable_scale.dart';

/// The hero block at the top of Today: the one inverted surface on the screen.
///
/// Mirrors the five states of the home-screen widget:
///   * live now — status pill, room CTA, subject, "24 min left"/"1 h 30 min
///     left", bar;
///   * next up — status pill, room CTA, subject, "STARTS IN" caption, big
///     countdown;
///   * all done / free day — outline check, message, next-class shelf;
///   * empty schedule — logo mark, "No classes scheduled".
///
/// The class name leads every class state and the countdown supports it. The
/// time and professor live in the schedule list, not in the hero. Layout
/// values come from the states board: 16px radius, 18/18/18/20 padding,
/// 30-blur/14-offset shadow, a 6px in-card progress bar, and the mock's 28px
/// status pill, 34px room CTA and 44px countdown.
class NextClassCard extends StatelessWidget {
  final String label;
  final String subject;
  final String room;

  /// Celebration shelf only: the next class's time range under its subject.
  /// Class states have no time line; the countdown carries that job.
  final String time;

  /// Right side of the live row ("Ends in 24m"). The next-up state uses the
  /// big [countdown] instead, and the shelf uses this as the starts-in line.
  final String whenText;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? celebrationTitle;
  final String? celebrationSubtitle;
  final IconData? celebrationIcon;
  final String? dayPillText;

  /// Time left in the live class, or time until the next-up class. The card
  /// turns this into structured big-number/small-unit type.
  final Duration? countdown;

  /// For the "In class" hero: elapsed fraction (0..1), drawn as a 6px rounded
  /// gradient bar inside the card. Null = no bar.
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
    final isCelebration =
        celebrationTitle != null || celebrationSubtitle != null;

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
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 30,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Material(
              color: const Color(0xFF151515),
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                  child: _empty
                      ? _EmptyBody(textTheme: textTheme)
                      : isCelebration
                      ? _CelebrationBody(
                          title: celebrationTitle ?? label,
                          subtitle: celebrationSubtitle ?? subject,
                          icon: celebrationIcon,
                          dayPillText: dayPillText,
                          whenText: whenText,
                          subject: subject,
                          time: time,
                          onTeaserTap: onTeaserTap,
                          textTheme: textTheme,
                        )
                      : _ClassBody(
                          label: label,
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
            ),
          ),
        ),
      ),
    );
  }
}

/// The class hero: status row, subject, structured countdown, progress.
class _ClassBody extends StatelessWidget {
  const _ClassBody({
    required this.label,
    required this.subject,
    required this.room,
    required this.countdown,
    required this.isLive,
    required this.liveProgress,
    required this.liveRemaining,
    required this.textTheme,
  });

  final String label;
  final String subject;
  final String room;
  final Duration? countdown;
  final bool isLive;
  final double? liveProgress;
  final Duration? liveRemaining;
  final TextTheme textTheme;

  static const _live = Color(0xFFFF8A5C);

  @override
  Widget build(BuildContext context) {
    final showRoomCta = room.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _StatusPill(label: label, isLive: isLive),
            const SizedBox(width: 12),
            // The room is the second thing you look for after the class name,
            // so it stays on the status line in both states. Live used to put
            // "Ends in 24m" here; the big countdown now carries that instead
            // of repeating it.
            if (showRoomCta)
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _RoomCta(room: room, textTheme: textTheme),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          subject,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontSize: 20,
            height: 26 / 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        if (countdown != null) ...[
          SizedBox(height: isLive ? 10 : 12),
          // Without this caption the big numbers read like the class's
          // duration. Live units already say "left"; the caption still names
          // what the number counts down to.
          if (isLive) ...[
            Text(
              'ENDS IN',
              style: textTheme.labelSmall?.copyWith(
                color: const Color(0xFF9A9A9A),
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 4),
          ] else ...[
            Text(
              'STARTS IN',
              style: textTheme.labelSmall?.copyWith(
                color: const Color(0xFF9A9A9A),
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 4),
          ],
          _HeroCountdown(
            duration: countdown!,
            isLive: isLive,
            textTheme: textTheme,
          ),
        ],
        if (isLive && liveProgress != null) ...[
          const SizedBox(height: 20),
          _LiveProgressBar(progress: liveProgress!, remaining: liveRemaining),
        ],
      ],
    );
  }
}

/// "Live now" (with the pulsing dot) or "Next up".
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.isLive});

  final String label;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      height: 28,
      padding: EdgeInsets.only(left: isLive ? 10 : 12, right: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF262626),
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive) ...[
            const LivePulse(
              size: 8,
              color: _ClassBody._live,
              haloOpacity: 0.22,
            ),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFF2F2F2),
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Room CTA in the top-right, only for the next-up state.
class _RoomCta extends StatelessWidget {
  const _RoomCta({required this.room, required this.textTheme});

  final String room;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: false,
      label: 'Room $room',
      excludeSemantics: true,
      child: Container(
        height: 34,
        padding: const EdgeInsets.only(left: 12, right: 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(17)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _NavArrow(size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                room,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF000000),
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Big structured countdown: 44px values with 16px units on the baseline.
class _HeroCountdown extends StatelessWidget {
  const _HeroCountdown({
    required this.duration,
    required this.isLive,
    required this.textTheme,
  });

  final Duration duration;
  final bool isLive;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final parts = _countdownParts(duration, isLive: isLive);
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
              color: Colors.white,
              fontSize: 44,
              height: 52 / 44,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.32,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 4),
          Text(
            part.unit,
            style: textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF8E8E8E),
              fontSize: 16,
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

/// One icon + label pair in the class meta row.
class _MetaItem extends StatelessWidget {
  const _MetaItem({
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.color,
    required this.textTheme,
  });

  final IconData icon;
  final Color iconColor;
  final String text;
  final Color color;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: iconColor),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: color,
              fontSize: 13,
              height: 18 / 13,
              fontWeight: FontWeight.w400,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// The 6px in-card elapsed bar: rounded track, orange gradient fill.
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
          color: const Color(0xFF262626),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: f,
            heightFactor: 1,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFF8A5C), Color(0xFFFFA983)],
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

/// All-done / weekend / free-day hero: an outline check row and, when there
/// really is an upcoming class, the next-class shelf beneath.
class _CelebrationBody extends StatelessWidget {
  const _CelebrationBody({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.dayPillText,
    required this.whenText,
    required this.subject,
    required this.time,
    required this.textTheme,
    this.onTeaserTap,
  });

  final String title;
  final String subtitle;
  final IconData? icon;
  final String? dayPillText;
  final String whenText;
  final String subject;
  final String time;
  final TextTheme textTheme;

  /// Makes the "next class" shelf tappable (jump to that day on Week).
  final VoidCallback? onTeaserTap;

  static const _muted = Color(0xFF9A9A9A);

  @override
  Widget build(BuildContext context) {
    // The shelf only appears when there is an upcoming class to show. Without
    // one, the celebration stays compact instead of leaving an empty block.
    final hasUpNext =
        subject.trim().isNotEmpty ||
        whenText.trim().isNotEmpty ||
        (dayPillText?.trim().isNotEmpty ?? false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              ExcludeSemantics(
                child: Icon(icon, size: 28, color: Colors.white),
              ),
              const SizedBox(width: 14),
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
                      color: Colors.white,
                      fontSize: 19,
                      height: 1.26,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                  if (subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: _muted,
                        fontSize: 13,
                        height: 18 / 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (hasUpNext) ...[
          const SizedBox(height: 18),
          Semantics(
            button: onTeaserTap != null,
            enabled: onTeaserTap != null,
            label: onTeaserTap == null
                ? null
                : 'Show this class on the week view',
            excludeSemantics: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF252525),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTeaserTap,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (dayPillText != null && dayPillText!.isNotEmpty)
                              Container(
                                height: 22,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                ),
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  dayPillText!,
                                  style: textTheme.labelSmall?.copyWith(
                                    color: const Color(0xFF000000),
                                    fontSize: 10,
                                    height: 1.1,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            if (whenText.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  whenText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFFBDBDBD),
                                    fontSize: 12,
                                    height: 1.3,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.1,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
                            fontSize: 16,
                            height: 22 / 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                          ),
                        ),
                        if (time.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          _MetaItem(
                            icon: Icons.access_time_rounded,
                            iconColor: const Color(0xFF7D7D7D),
                            text: time.trim(),
                            color: _muted,
                            textTheme: textTheme,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Empty-schedule hero. The board says the app uses a dedicated empty card;
/// this keeps the widget's logo + copy inside that same card.
class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.textTheme});

  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(6),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: const _LogoMark(),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No classes scheduled',
                style: textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontSize: 17,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Add a class or import a timetable to begin.',
                style: textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFB3B3B3),
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

/// The three-bar Klasify mark used by the widget's empty state.
class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _LogoMarkPainter());
}

class _LogoMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 40;
    final black = Paint()..color = const Color(0xFF000000);
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
      black,
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
      black,
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
      black,
    );
    canvas.drawCircle(
      Offset(4 * unit / 40, 11 * unit / 40),
      2 * unit / 40,
      orange,
    );
  }

  @override
  bool shouldRepaint(covariant _LogoMarkPainter oldDelegate) => false;
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
/// "2d 3h". Live countdowns read "24 min left" or "1 h 30 min left";
/// next-up ones are labelled "STARTS IN" above the numbers.
List<({String value, String unit})> _countdownParts(
  Duration duration, {
  required bool isLive,
}) {
  final totalMinutes = duration.inMinutes.clamp(0, 7 * 24 * 60);
  final List<({String value, String unit})> parts;
  if (totalMinutes >= 1440) {
    final days = totalMinutes ~/ 1440;
    final hours = (totalMinutes % 1440) ~/ 60;
    parts = [
      (value: '$days', unit: 'd'),
      if (hours > 0) (value: '$hours', unit: 'h'),
    ];
  } else if (totalMinutes >= 60) {
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    parts = [
      (value: '$hours', unit: 'h'),
      if (minutes > 0) (value: '$minutes', unit: 'min'),
    ];
  } else {
    parts = [(value: '${totalMinutes == 0 ? 1 : totalMinutes}', unit: 'min')];
  }
  if (!isLive) return parts;

  // Only the final unit says "left": "24 min left", "1 h 30 min left".
  final last = parts.removeLast();
  return [...parts, (value: last.value, unit: '${last.unit} left')];
}

String _countdownSummary(Duration duration) {
  final parts = _countdownParts(duration, isLive: false);
  return parts.map((part) => '${part.value}${part.unit}').join(' ');
}
