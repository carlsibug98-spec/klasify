import 'package:flutter/material.dart';

import 'live_pulse.dart';
import 'pressable_scale.dart';

/// The hero block at the top of Today, in the v52 widget design: a dark card
/// with a status pill, the class title, and — when there is really a class —
/// a white room chip and the instructor.
///
/// It is the only inverted surface on the screen, so the eye lands here first.
///
/// Layout (from the design): status pill ("In class" with the orange live dot,
/// or "Upcoming") sits opposite the start/end text on top, the title below,
/// then a bottom row with the room chip and the teacher. The all-done and
/// weekend variants swap the class rows for a check icon and a compact
/// "next class" shelf.
class NextClassCard extends StatelessWidget {
  final String label;
  final String subject;
  final String room;
  final String professor;
  final String time;
  final String whenText;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? celebrationTitle;
  final String? celebrationSubtitle;
  final IconData? celebrationIcon;
  final String? dayPillText;

  const NextClassCard({
    super.key,
    required this.label,
    required this.subject,
    required this.room,
    this.professor = '',
    required this.time,
    required this.whenText,
    this.onTap,
    this.onLongPress,
    this.celebrationTitle,
    this.celebrationSubtitle,
    this.celebrationIcon,
    this.dayPillText,
  });

  /// Celebration only ("Good job"). Shows no class details.
  const NextClassCard.celebration({
    super.key,
    required String title,
    required String subtitle,
    required IconData icon,
  }) : label = '',
       subject = '',
       room = '',
       professor = '',
       time = '',
       whenText = '',
       onTap = null,
       onLongPress = null,
       celebrationTitle = title,
       celebrationSubtitle = subtitle,
       celebrationIcon = icon,
       dayPillText = null;

  const NextClassCard.empty({super.key})
    : label = 'Get started',
      subject = 'Add a class or import a schedule to begin.',
      room = '',
      professor = '',
      time = '',
      whenText = '',
      onTap = null,
      onLongPress = null,
      celebrationTitle = null,
      celebrationSubtitle = null,
      celebrationIcon = null,
      dayPillText = null;

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
        label: [
          if (celebrationTitle != null) celebrationTitle!,
          if (celebrationSubtitle != null) celebrationSubtitle!,
          if (dayPillText != null) dayPillText!,
          label,
          subject,
          time,
          room,
          professor,
          whenText,
        ].where((value) => value.trim().isNotEmpty).join('. '),
        child: PressableScale(
          enabled: onTap != null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x38000000),
                  blurRadius: 48,
                  offset: Offset(0, 24),
                ),
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: const Color(0xFF151515),
              borderRadius: BorderRadius.circular(28),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                borderRadius: BorderRadius.circular(28),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: isCelebration
                      ? _CelebrationBody(
                          title: celebrationTitle ?? label,
                          subtitle: celebrationSubtitle ?? subject,
                          icon: celebrationIcon,
                          dayPillText: dayPillText,
                          whenText: whenText,
                          subject: subject,
                          time: time,
                          room: room.trim(),
                          textTheme: textTheme,
                        )
                      : _ClassBody(
                          label: label,
                          subject: subject.trim(),
                          room: room.trim(),
                          professor: professor.trim(),
                          time: time.trim(),
                          whenText: whenText,
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

/// The class hero: pill + when-text on top, title, time, room chip + teacher.
class _ClassBody extends StatelessWidget {
  const _ClassBody({
    required this.label,
    required this.subject,
    required this.room,
    required this.professor,
    required this.time,
    required this.whenText,
    required this.textTheme,
  });

  final String label;
  final String subject;
  final String room;
  final String professor;
  final String time;
  final String whenText;
  final TextTheme textTheme;

  static const _live = Color(0xFFFF8A5C);
  static const _muted = Color(0xFFB3B3B3);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _StatusPill(label: label),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                whenText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: _whenStyle,
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
            fontSize: 25,
            height: 1.16,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.5,
          ),
        ),
        if (time.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            time,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              height: 1.33,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (room.isNotEmpty)
              Flexible(
                child: Semantics(
                  button: false,
                  label: 'Room $room',
                  excludeSemantics: true,
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.only(left: 14, right: 18),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.all(Radius.circular(22)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // The mock draws the room affordance as a stroked
                        // navigation arrow, not a map pin.
                        const _NavArrow(size: 20),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            room,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF000000),
                              fontSize: 15,
                              height: 1.2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (professor.isNotEmpty) ...[
              Flexible(
                flex: 0,
                fit: FlexFit.loose,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Flexible(
                      flex: 0,
                      child: Icon(
                        Icons.person_outline_rounded,
                        size: 16,
                        color: _muted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      fit: FlexFit.loose,
                      child: Text(
                        professor,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: _muted,
                          fontSize: 14,
                          height: 1.3,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  TextStyle? get _whenStyle => textTheme.bodyMedium?.copyWith(
    color: Colors.white,
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w600,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// "In class" (with the live dot) or "Upcoming".
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isLive = label == 'In class';
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF2A2A2A),
        borderRadius: BorderRadius.all(Radius.circular(13)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive) ...[
            const LivePulse(
              size: 8,
              color: _ClassBody._live,
              haloOpacity: 0.25,
            ),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: Colors.white,
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

/// All-done / weekend / free-day hero, from the widget design: a check row
/// and — when there really is an upcoming class — a compact shelf beneath.
class _CelebrationBody extends StatelessWidget {
  const _CelebrationBody({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.dayPillText,
    required this.whenText,
    required this.subject,
    required this.time,
    required this.room,
    required this.textTheme,
  });

  final String title;
  final String subtitle;
  final IconData? icon;
  final String? dayPillText;
  final String whenText;
  final String subject;
  final String time;
  final String room;
  final TextTheme textTheme;

  static const _muted = Color(0xFFB3B3B3);

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
                child: Icon(icon, size: 24, color: Colors.white),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontSize: 19,
                      height: 1.26,
                      fontWeight: FontWeight.w600,
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
                        height: 1.38,
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
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF252525),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (dayPillText != null && dayPillText!.isNotEmpty)
                      Container(
                        height: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                        ),
                        child: Text(
                          dayPillText!,
                          style: textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF000000),
                            fontSize: 11,
                            height: 1.1,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.45,
                          ),
                        ),
                      ),
                    if (whenText.isNotEmpty)
                      Flexible(
                        child: Text(
                          whenText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: _muted,
                            fontSize: 13,
                            height: 1.3,
                            fontWeight: FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.33,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (time.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        time,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: _muted,
                          fontSize: 14,
                          height: 1.3,
                          fontWeight: FontWeight.w400,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
                if (room.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    room,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: _muted,
                      fontSize: 13,
                      height: 1.38,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
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
