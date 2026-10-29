import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../routes/app_routes.dart';
import '../services/onboarding_store.dart';
import '../theme/app_theme.dart';
import '../widgets/first_run_options.dart';
import '../widgets/pressable_scale.dart';

/// The three onboarding pages, straight from the design:
/// 1. Welcome (dark cover, stacked next-class widget)
/// 2. Add your timetable (scan/add tiles with the example card)
/// 3. Stay on track (reminder card with toggle + chips, backup card)
///
/// All previews are static, inert compositions — the real interactive
/// versions live in FirstRunOptions and the Reminders screen.
class _OnboardingPageIndex {
  const _OnboardingPageIndex({
    required this.title,
    required this.body,
    required this.kicker,
    required this.previewDescription,
    required this.preview,
  });

  final String title;
  final String body;

  /// Small-caps section label with the black dot, e.g. "ADD & SCAN".
  final String kicker;

  /// Name used in the preview's semantics description.
  final String previewDescription;

  /// A static, non-interactive preview of the real UI.
  final WidgetBuilder preview;
}

final _pages = <_OnboardingPageIndex>[
  _OnboardingPageIndex(
    title: 'Know what’s\nnext.',
    body:
        'Today shows the class in progress and what’s coming up, with '
        'its room. Week lays out every day. Everything stays on your '
        'phone.',
    kicker: 'WELCOME',
    previewDescription: 'Welcome cover: Klasify logo and a next-class example',
    preview: (_) => const _WelcomeWidget(),
  ),
  _OnboardingPageIndex(
    title: 'Add your timetable',
    body:
        'Scan a photo or PDF, or add classes by hand. Klasify flags any '
        'room to check, and nothing is saved until you confirm it.',
    kicker: 'ADD & SCAN',
    previewDescription:
        'Two ways to add a class: scan a photo or PDF, or '
        'type one in, with a detected class example that flags '
        'a missing room.',
    preview: (_) =>
        FirstRunOptions(onScan: () {}, onAdd: () {}, showExample: true),
  ),
  _OnboardingPageIndex(
    title: 'Stay on track',
    body:
        'Get a reminder before each class, every week, at the time you '
        'choose. Everything stays on your phone, so export a backup '
        'before you switch.',
    kicker: 'REMINDERS',
    previewDescription:
        'Reminder settings preview: a weekly reminder that '
        'fires before class with a choice of lead time, and schedule '
        'backup.',
    preview: (_) => const _RemindersPreview(),
  ),
];

class OnboardingScreen extends StatefulWidget {
  /// True when opened again from Settings: finishing just closes the screen.
  final bool isReplay;
  const OnboardingScreen({super.key, this.isReplay = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (widget.isReplay) {
      Navigator.pop(context);
      return;
    }
    await OnboardingStore.markCompleted();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, AppRoutes.home);
  }

  Future<void> _startWith(String route) async {
    await OnboardingStore.markCompleted();
    if (!mounted) return;
    await Navigator.pushNamed(context, route);
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, AppRoutes.home);
  }

  /// What the primary button on page [i] does: advance, or leave on the last.
  void _advanceFrom(int i) {
    if (i == _pages.length - 1) {
      if (widget.isReplay) {
        _finish();
      } else {
        _startWith(AppRoutes.classForm);
      }
    } else {
      _moveToPage(i + 1);
    }
  }

  void _moveToPage(int page) {
    if (MediaQuery.of(context).disableAnimations) {
      _controller.jumpToPage(page);
      return;
    }
    _controller.animateToPage(
      page,
      duration: AppTheme.motionPage,
      curve: AppTheme.motionEaseInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // System back steps to the previous page before leaving the screen.
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _moveToPage(_page - 1);
        }
      },
      child: Scaffold(
        body: PageView.builder(
          controller: _controller,
          itemCount: _pages.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: _buildPage,
        ),
      ),
    );
  }

  Widget _buildPage(BuildContext context, int i) {
    final page = _pages[i];
    final isCover = i == 0;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final reduced = MediaQuery.of(context).disableAnimations;

    // The cover sits on the inverted surface, so all its ink inverts too.
    final foreground = isCover ? scheme.onInverseSurface : scheme.onSurface;
    final muted = isCover
        ? foreground.withValues(alpha: 0.78)
        : scheme.onSurfaceVariant;

    // Status bar icons must contrast with the page behind them: light icons on
    // the dark cover (light scheme), the theme default everywhere else.
    final overlay = isCover
        ? (scheme.brightness == Brightness.light
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark)
        : (scheme.brightness == Brightness.light
              ? SystemUiOverlayStyle.dark
              : SystemUiOverlayStyle.light);

    final isLastPage = i == _pages.length - 1;
    final ctaLabel = !isLastPage
        ? 'Continue'
        : widget.isReplay
        ? 'Done'
        : 'Add my first class';
    // First run only: a quiet exit that skips the form. Replay already has a
    // Close in the header, so a second exit would be noise there.
    final showExploreFirst = isLastPage && !widget.isReplay;
    // The dots below already announce the step to screen readers. The
    // readable counter is a sighted companion, and it steps aside when large
    // text needs the header width for the brand and the exit.
    final showStepCounter =
        !isCover && MediaQuery.textScalerOf(context).scale(1.0) <= 1.3;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Container(
        key: ValueKey('onboarding-page-$i'),
        color: isCover ? scheme.inverseSurface : scheme.surface,
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header: brand on every page; the tour pages add a quiet
                  // step count, and every page keeps one skip/close exit.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(isCover ? 10 : 8),
                          child: Image.asset(
                            Theme.of(context).brightness == Brightness.light
                                ? 'assets/klasify_logo_light.png'
                                : 'assets/klasify_logo.png',
                            width: isCover ? 36 : 28,
                            height: isCover ? 36 : 28,
                            excludeFromSemantics: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Flexible so extreme text scale truncates the
                        // wordmark instead of pushing the exit off the edge.
                        Expanded(
                          child: Text(
                            'Klasify',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium?.copyWith(
                              color: foreground,
                              fontSize: isCover ? null : 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (showStepCounter) ...[
                          const SizedBox(width: 8),
                          ExcludeSemantics(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${i + 1}'.padLeft(2, '0'),
                                    style: TextStyle(
                                      color: foreground,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  TextSpan(
                                    text:
                                        ' / ${_pages.length.toString().padLeft(2, '0')}',
                                  ),
                                ],
                              ),
                              style: textTheme.labelLarge?.copyWith(
                                color: muted,
                                fontSize: 12,
                                height: 1.2,
                                letterSpacing: 0.4,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        TextButton(
                          onPressed: _finish,
                          style: TextButton.styleFrom(
                            foregroundColor: muted,
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            textStyle: textTheme.labelLarge?.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          child: Text(widget.isReplay ? 'Close' : 'Skip'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        key: ValueKey('onboarding-scroll-$i'),
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            // The scroll box can be shorter than its padding
                            // (keyboard open, portrait shell) — a negative
                            // minimum height would crash the layout.
                            minHeight: math.max(0, constraints.maxHeight - 24),
                          ),
                          child: Align(
                            // Every page composes around the same optical
                            // centre: the cover does it with its own stack, and
                            // the tour pages centre their preview + copy instead
                            // of leaving the lower half of the page empty.
                            alignment: Alignment.center,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: _StaggeredIn(
                                key: ValueKey('onboarding-stagger-$i'),
                                enabled: !reduced,
                                children: [
                                  if (!isCover) ...[
                                    // Editorial eyebrow: what section you're in,
                                    // with the "Example" qualifier next to it.
                                    // The filled kicker anchors the page; the
                                    // outlined qualifier stays quiet.
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 14,
                                      ),
                                      child: Row(
                                        children: [
                                          // Flexed so extreme text scale
                                          // truncates the chips instead of
                                          // overflowing the eyebrow row.
                                          Flexible(
                                            child: _SectionChip(
                                              label: page.kicker,
                                              background: scheme.primary,
                                              foreground: scheme.onPrimary,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: _SectionChip(
                                              label: 'Example',
                                              background: Colors.transparent,
                                              foreground:
                                                  scheme.onSurfaceVariant,
                                              border: scheme.outlineVariant,
                                              dot: false,
                                              small: true,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    _Parallax(
                                      controller: _controller,
                                      pageIndex: i,
                                      enabled: !reduced,
                                      child: _Preview(page: page),
                                    ),
                                  ],
                                  Padding(
                                    padding: EdgeInsets.only(
                                      top: isCover ? 0 : 28,
                                      bottom: 0,
                                    ),
                                    child: Text(
                                      page.title,
                                      maxLines: isCover ? null : 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: isCover
                                          ? textTheme.displaySmall?.copyWith(
                                              color: foreground,
                                              fontSize: 46,
                                              height: 1.05,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -1.6,
                                            )
                                          : textTheme.headlineMedium?.copyWith(
                                              fontSize: 30,
                                              height: 1.12,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.9,
                                            ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.only(
                                      top: isCover ? 16 : 12,
                                    ),
                                    child: Text(
                                      page.body,
                                      style: textTheme.bodyLarge?.copyWith(
                                        color: muted,
                                        fontSize: 17,
                                        height: 1.55,
                                      ),
                                    ),
                                  ),
                                  // The cover still gets its preview: the stacked
                                  // next-class widget beneath the title and body,
                                  // per the welcome mock.
                                  if (isCover)
                                    _Parallax(
                                      controller: _controller,
                                      pageIndex: i,
                                      enabled: !reduced,
                                      child: _Preview(page: page),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: _ProgressDots(
                          key: const ValueKey('onboarding-progress'),
                          count: _pages.length,
                          current: i,
                          inverted: isCover,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      showExploreFirst ? 8 : 14,
                      20,
                      0,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // The cover's CTA inverts the page: white button
                            // on black, full press physics. Everything else
                            // is the theme's black button.
                            SizedBox(
                              width: double.infinity,
                              child: PressableScale(
                                enabled: i == _page,
                                child: FilledButton(
                                  onPressed: i == _page
                                      ? () => _advanceFrom(i)
                                      : null,
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(64, 56),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        AppTheme.controlRadius,
                                      ),
                                    ),
                                    backgroundColor: isCover
                                        ? scheme.onInverseSurface
                                        : null,
                                    foregroundColor: isCover
                                        ? scheme.inverseSurface
                                        : null,
                                  ),
                                  child: Text(
                                    ctaLabel,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (showExploreFirst)
                              TextButton(
                                onPressed: _finish,
                                style: TextButton.styleFrom(
                                  foregroundColor: scheme.onSurfaceVariant,
                                  minimumSize: const Size(0, 48),
                                  padding: EdgeInsets.zero,
                                  textStyle: textTheme.labelLarge?.copyWith(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                child: const Text('Explore first'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps a page's static preview in its common chrome: semantics container,
/// non-interactive (IgnorePointer) and invisible to screen readers beyond a
/// description.
class _Preview extends StatelessWidget {
  const _Preview({required this.page});

  final _OnboardingPageIndex page;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: page.previewDescription,
      child: ExcludeSemantics(
        child: IgnorePointer(child: page.preview(context)),
      ),
    );
  }
}

/// Small-caps section chip with the leading dot ("ADD & SCAN") or the plain
/// qualifier pill ("Example"), exactly as the design's eyebrow row.
class _SectionChip extends StatelessWidget {
  const _SectionChip({
    required this.label,
    required this.background,
    required this.foreground,
    this.dot = true,
    this.small = false,
    this.border,
  });

  final String label;
  final Color background;
  final Color foreground;
  final bool dot;
  final bool small;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      height: small ? 26 : 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(small ? 13 : 14),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: foreground,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Text(
              small ? label : label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: foreground,
                fontSize: small ? 12 : 11,
                height: 1.2,
                fontWeight: small ? FontWeight.w600 : FontWeight.w800,
                letterSpacing: small ? 0 : 1.32,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The cover's stacked next-class widget: two quiet layers behind and the
/// light "Upcoming" widget card in front — the v52 hero design, small.
class _WelcomeWidget extends StatelessWidget {
  const _WelcomeWidget();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // The card is a decorative mock, so its height follows large text instead
    // of clipping or shrinking it. Capped so the cover stays proportionate.
    final textScale = MediaQuery.textScalerOf(
      context,
    ).scale(1.0).clamp(1.0, 2.0);
    final cardHeight = 150 + (textScale - 1) * 60;
    return Padding(
      padding: const EdgeInsets.only(top: 44),
      child: SizedBox(
        height: cardHeight + 46,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The next-class card itself.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: cardHeight,
              child: Semantics(
                container: true,
                label:
                    'Example of the next-class widget: Next up, Design Class, '
                    'starts in 2 hours 12 minutes, Room 242-B.',
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.onInverseSurface,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x26000000),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
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
                            Container(
                              height: 26,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Text(
                                'Next up',
                                style: textTheme.labelMedium?.copyWith(
                                  color: scheme.onSurface,
                                  fontSize: 12,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Spacer(),
                            // Flexible so extreme text scale truncates the
                            // room instead of overflowing the card.
                            Flexible(
                              child: Container(
                                height: 26,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.near_me_rounded,
                                      size: 13,
                                      color: scheme.onSurface,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        'Room 242-B',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textTheme.bodySmall?.copyWith(
                                          color: scheme.onSurface,
                                          fontSize: 12,
                                          height: 1.2,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Design Class',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleLarge?.copyWith(
                            color: scheme.onSurface,
                            fontSize: 22,
                            height: 1.18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.44,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // The mock's cover preview: the countdown reads as
                        // one quiet line under the title ("Starts in 1 h 46
                        // min") — the caption-over-countdown anatomy belongs
                        // to the real hero and launcher widget.
                        Text(
                          'Starts in 1 h 46 min',
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontSize: 14,
                            height: 20 / 14,
                            fontWeight: FontWeight.w400,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The reminders preview from the "Stay on track" design: the reminder card
/// with its on-toggle and lead chips, and the backup card beneath. Static —
/// the live version is the Reminders screen.
class _RemindersPreview extends StatelessWidget {
  const _RemindersPreview();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget card({required Widget child}) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // Same quiet stage as page 2's scan/type panel, so the two tour
        // previews read as one family.
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      size: 24,
                      color: scheme.onSurface,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Remind me before class',
                            style: textTheme.bodyLarge?.copyWith(
                              color: scheme.onSurface,
                              fontSize: 15,
                              height: 1.3,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Weekly, on your class days',
                            style: textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontSize: 13,
                              height: 1.38,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Static "on" toggle, drawn to the design (48x28 track,
                    // 22px thumb at the on side).
                    SizedBox(
                      width: 48,
                      height: 28,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: scheme.onPrimary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (final (index, lead) in const [5, 10, 15, 30].indexed)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: index == 3 ? 0 : 8),
                          child: Container(
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: lead == 10
                                  ? scheme.primary
                                  : scheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$lead min',
                              style: textTheme.bodySmall?.copyWith(
                                color: lead == 10
                                    ? scheme.onPrimary
                                    : scheme.onSurface,
                                fontSize: 13,
                                height: 1.2,
                                fontWeight: lead == 10
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          card(
            child: Row(
              children: [
                Icon(Icons.upload_outlined, size: 24, color: scheme.onSurface),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Back up your schedule',
                        style: textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurface,
                          fontSize: 15,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Export a file before switching phones',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                          height: 1.38,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Staggered entrance: children fade in and rise 14 px, one after another —
/// a 560 ms choreography in 14% beats. Onboarding is a first-run surface, so
/// it carries the app's whole delight budget; replays whenever the widget
/// remounts (each onboarding page keys its own), and snaps to the final state
/// when reduced motion is on.
class _StaggeredIn extends StatefulWidget {
  const _StaggeredIn({
    super.key,
    required this.children,
    required this.enabled,
  });

  final List<Widget> children;
  final bool enabled;

  @override
  State<_StaggeredIn> createState() => _StaggeredInState();
}

class _StaggeredInState extends State<_StaggeredIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(_StaggeredIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reduced motion turned on mid-flight: land instantly.
    if (!widget.enabled && _controller.value != 1) {
      _controller.value = 1;
    } else if (widget.enabled && !oldWidget.enabled && _controller.value < 1) {
      _controller.forward(from: _controller.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final interval = Interval(
                (i * 0.14).clamp(0.0, 0.72),
                1.0,
                curve: AppTheme.motionEaseOut,
              );
              final t = interval.transform(_controller.value);
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * 14),
                  child: child,
                ),
              );
            },
            child: widget.children[i],
          ),
      ],
    );
  }
}

/// Content lags the page swipe for a quiet sense of depth: the preview drifts
/// a step behind the page's own motion. Costs one Transform per layer.
/// Disabled for reduced motion.
class _Parallax extends StatelessWidget {
  const _Parallax({
    required this.controller,
    required this.pageIndex,
    required this.enabled,
    required this.child,
  });

  /// How far the preview trails the page at most, in logical pixels.
  static const double _shift = 24;

  final PageController controller;
  final int pageIndex;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        double offset = 0;
        if (enabled &&
            controller.hasClients &&
            controller.position.haveDimensions) {
          final page = controller.page ?? pageIndex.toDouble();
          offset = ((page - pageIndex) * _shift).clamp(-_shift, _shift);
        }
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
      child: child,
    );
  }
}

/// Story-style progress dots, straight from the design: the active page is a
/// 22x6 bar, the rest 6x6 dots.
class _ProgressDots extends StatelessWidget {
  const _ProgressDots({
    super.key,
    required this.count,
    required this.current,
    required this.inverted,
  });

  final int count;
  final int current;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = inverted ? scheme.onInverseSurface : scheme.primary;
    final inactive = inverted
        ? scheme.onInverseSurface.withValues(alpha: 0.44)
        : scheme.outline;

    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Step ${current + 1} of $count',
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              AnimatedContainer(
                width: i == current ? 28 : 6,
                height: 6,
                duration: AppTheme.motionDuration(
                  context,
                  AppTheme.motionStandard,
                ),
                curve: AppTheme.motionEaseOut,
                decoration: BoxDecoration(
                  color: i == current ? active : inactive,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
