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
        'Your timetable, close at hand. What’s on now, what’s next, and '
        'the week ahead. Everything stays on your phone.',
    kicker: 'WELCOME',
    previewDescription: 'Welcome cover: Klasify logo and a next-class example',
    preview: (_) => const _WelcomeWidget(),
  ),
  _OnboardingPageIndex(
    title: 'Add your timetable',
    body:
        'Scan a photo or PDF, or type classes in. You review every time '
        'and room before anything is saved.',
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
        'Get a nudge before class. Everything stays on your phone, so '
        'export a backup before you switch.',
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
    final topInset = MediaQuery.paddingOf(context).top;

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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Container(
        key: ValueKey('onboarding-page-$i'),
        color: isCover ? scheme.inverseSurface : scheme.surface,
        child: Stack(
          children: [
            // Pages 2 and 3 carry a giant ghost step numeral behind
            // everything — quiet editorial texture that moves against the
            // swipe for depth.
            if (!isCover)
              Positioned(
                top: topInset > 6 ? topInset - 6 : 0,
                right: 12,
                child: _Parallax(
                  controller: _controller,
                  pageIndex: i,
                  enabled: !reduced,
                  factor: -16,
                  child: ExcludeSemantics(
                    child: Text(
                      '$i',
                      style: textTheme.displaySmall?.copyWith(
                        fontSize: 168,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -8,
                        color: scheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                ),
              ),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header: brand on the cover, skip/close on every page.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                    child: Row(
                      children: [
                        if (isCover) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.asset(
                              'assets/klasify_logo.png',
                              width: 36,
                              height: 36,
                              excludeFromSemantics: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Flexible so extreme text scale truncates the
                          // wordmark instead of pushing Skip off the edge.
                          Expanded(
                            child: Text(
                              'Klasify',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleMedium?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                        if (!isCover) const Spacer(),
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
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight - 24,
                          ),
                          child: Align(
                            alignment: isCover
                                ? Alignment.center
                                : Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: _StaggeredIn(
                                key: ValueKey('onboarding-stagger-$i'),
                                enabled: !reduced,
                                children: [
                                  if (!isCover) ...[
                                    // Editorial eyebrow: what section you're in,
                                    // with the "Example" qualifier next to it.
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 4,
                                        bottom: 12,
                                      ),
                                      child: Row(
                                        children: [
                                          // Flexed so extreme text scale
                                          // truncates the chips instead of
                                          // overflowing the eyebrow row.
                                          Flexible(
                                            child: _SectionChip(
                                              label: page.kicker,
                                              background:
                                                  scheme.surfaceContainerHigh,
                                              foreground: scheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: _SectionChip(
                                              label: 'EXAMPLE',
                                              background:
                                                  scheme.surfaceContainerHigh,
                                              foreground:
                                                  scheme.onSurfaceVariant,
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
                                      top: isCover ? 0 : 26,
                                      bottom: 0,
                                    ),
                                    child: Text(
                                      page.title,
                                      maxLines: isCover ? null : 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: isCover
                                          ? textTheme.displaySmall?.copyWith(
                                              color: foreground,
                                              fontSize: 42,
                                              height: 1.1,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -1.47,
                                            )
                                          : textTheme.headlineSmall?.copyWith(
                                              fontSize: 26,
                                              height: 1.23,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.52,
                                            ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.only(
                                      top: isCover ? 16 : 10,
                                    ),
                                    child: Text(
                                      page.body,
                                      style: textTheme.bodyLarge?.copyWith(
                                        color: muted,
                                        fontSize: 17,
                                        height: 1.53,
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
  });

  final String label;
  final Color background;
  final Color foreground;
  final bool dot;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      height: small ? 24 : 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(small ? 12 : 14),
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
              small ? 'Example' : label.toUpperCase(),
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
    return Padding(
      padding: const EdgeInsets.only(top: 44),
      child: SizedBox(
        height: 196,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Two receding layers behind the card, top-aligned toward it.
            Positioned(
              left: 28,
              right: 28,
              top: 28,
              height: 128,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF151515),
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              top: 14,
              height: 128,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF242424),
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 136,
              child: Semantics(
                container: true,
                label:
                    'Example of the next-class widget: Design Class, '
                    '4:00 PM to 6:00 PM, Room 242-B, starting at 4:00 PM.',
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.onInverseSurface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                'Upcoming',
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
                            // start clock instead of overflowing the card.
                            Flexible(
                              child: Text(
                                'Starts 4:00 PM',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 13,
                                  height: 1.2,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                            Text(
                              '4:00 PM - 6:00 PM · Room 242-B',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontSize: 15,
                                height: 1.33,
                                fontWeight: FontWeight.w500,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
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
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
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

/// Content lags the page swipe for a quiet sense of depth — the ghost numeral
/// moves the opposite way ([factor] < 0), so the two layers shear against
/// each other. Costs one Transform per layer. Disabled for reduced motion.
class _Parallax extends StatelessWidget {
  const _Parallax({
    required this.controller,
    required this.pageIndex,
    required this.enabled,
    this.factor = 24.0,
    required this.child,
  });

  final PageController controller;
  final int pageIndex;
  final bool enabled;
  final double factor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        double shift = 0;
        if (enabled &&
            controller.hasClients &&
            controller.position.haveDimensions) {
          final page = controller.page ?? pageIndex.toDouble();
          final limit = factor.abs();
          shift = ((page - pageIndex) * factor).clamp(-limit, limit);
        }
        return Transform.translate(offset: Offset(shift, 0), child: child);
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
                width: i == current ? 22 : 6,
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
