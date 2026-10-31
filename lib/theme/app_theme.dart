import 'package:flutter/material.dart';

/// Klasify theme: black and white, with one signal colour for "now".
///
/// Core colours are black, white and greys. Semantic colours stay: live orange
/// marks "happening now", and green, ochre and red carry success, warning and error. Layout and motion tokens keep
/// their original names so every screen and test keeps compiling.
class AppTheme {
  AppTheme._();

  // ---- Motion tokens ----
  static const Duration motionFast = Duration(milliseconds: 120);
  static const Duration motionStandard = Duration(milliseconds: 180);
  static const Duration motionPage = Duration(milliseconds: 220);
  static const Duration motionToggle = Duration(milliseconds: 160);
  static const Cubic motionEaseOut = Cubic(0.23, 1, 0.32, 1);
  static const Cubic motionEaseInOut = Cubic(0.77, 0, 0.175, 1);

  /// Constant motion such as progress bars.
  static const Curve motionLinear = Curves.linear;

  static Duration motionDuration(BuildContext context, Duration duration) =>
      MediaQuery.of(context).disableAnimations ? Duration.zero : duration;

  // ---- Layout tokens ----
  static const double pageInset = 20;
  static const double pageContentMaxWidth = 1100;
  static const double sectionGap = 28;
  static const double itemGap = 12;

  /// Cards and the hero block.
  static const double cardRadius = 16;

  /// Buttons, fields and panels inside cards.
  static const double controlRadius = 16;

  /// Small chips such as the day selector.
  static const double chipRadius = 12;

  /// Class blocks on the timeline and time labels.
  static const double blockRadius = 10;

  /// Bottom sheets are the most rounded surface in the app.
  static const double sheetRadius = 28;

  // Sheet and card insets used by the class details sheet.
  static const double tightGap = 8;
  static const double sheetInset = 24;
  static const double cardInset = 16;
  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(
    pageInset,
    16,
    pageInset,
    24,
  );

  // ---- Card edge (option C): hairline + tight ambient shadow ----
  // Content cards get a 1px hairline so their edge survives the low-contrast
  // fills, plus a two-layer ambient shadow in light mode. Dark mode lifts
  // with luminance instead: a black shadow on the pure-black scaffold renders
  // nothing, so the resting card fill rises one step (see cardFillColorOf).
  // Values are the approved depth study (download/klasify-card-depth-mockup).
  static const Color _cardHairlineLight = Color(0x12000000); // black @ 7%
  static const Color _cardHairlineDark = Color(0x12FFFFFF); // white @ 7%

  /// Hairline for content cards (class cards and the shared Card theme).
  static BorderSide cardBorderSideOf(ColorScheme scheme) => BorderSide(
    color: scheme.brightness == Brightness.dark
        ? _cardHairlineDark
        : _cardHairlineLight,
  );

  /// Two-layer ambient shadow for content cards; empty in dark mode where
  /// the shadow would render nothing on the black scaffold.
  static List<BoxShadow> cardShadowsOf(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const []
      : const [
          BoxShadow(
            color: Color(0x0F000000), // black @ 6%
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(
            color: Color(0x14000000), // black @ 8%
            offset: Offset(0, 4),
            blurRadius: 12,
          ),
        ];

  /// Content-card fill. Light keeps the scheme containers; dark raises the
  /// resting card from #151515 to #181818 so the hairline has body. The
  /// "next up" card stays one step higher in both modes.
  static Color cardFillColorOf(ColorScheme scheme, {bool isNext = false}) {
    if (scheme.brightness == Brightness.dark) {
      return isNext
          ? scheme.surfaceContainerHighest
          : const Color(0xFF181818);
    }
    return isNext
        ? scheme.surfaceContainerHighest
        : scheme.surfaceContainer;
  }

  // ---- Status colours ----
  static const Color success = Color(0xFF1F6B4A);
  static const Color onSuccess = Color(0xFFFFFFFF);

  /// Signal colour. Only used for "happening now" and the live timeline marker.
  static const Color _live = Color(0xFFB43C1C);
  static const Color _liveDark = Color(0xFFFF8A5C);

  static Color placeholderFor(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFF9A9A9A)
      : const Color(0xFF6B6B6B);

  static Color disabledForegroundFor(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFF6B6B6B)
      : const Color(0xFF4A4A4A);

  static Color disabledSecondaryForegroundFor(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFF6B6B6B)
      : const Color(0xFF8A8A8A);

  static Color liveOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _liveDark : _live;

  static Color successBackgroundOf(BuildContext context) =>
      successBackgroundFor(Theme.of(context).colorScheme);

  static Color successForegroundOf(BuildContext context) =>
      successForegroundFor(Theme.of(context).colorScheme);

  static Color warningBackgroundOf(BuildContext context) =>
      warningBackgroundFor(Theme.of(context).colorScheme);

  static Color warningForegroundOf(BuildContext context) =>
      warningForegroundFor(Theme.of(context).colorScheme);

  static Color successBackgroundFor(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFF0C2D22)
      : const Color(0xFFD5EADF);

  static Color successForegroundFor(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFFD5EADF)
      : const Color(0xFF0C2D22);

  static Color warningBackgroundFor(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFF3F2A00)
      : const Color(0xFFFFEDC2);

  static Color warningForegroundFor(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFFFFEDC2)
      : const Color(0xFF3F2A00);

  /// Accent for action labels ("Undo") on inverse-surface toasts. Amber on
  /// the black toast, dark ochre on the white one, so the action stays
  /// findable and inside contrast in both themes.
  static Color toastActionFor(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFF3F2A00)
      : const Color(0xFFFFD08A);

  // ---- Light ----
  static const ColorScheme _lightScheme = ColorScheme.light(
    primary: Color(0xFF000000), // black: actions and selection
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE6E6E6),
    onPrimaryContainer: Color(0xFF000000),
    secondary: Color(0xFF4A4A4A),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFF4F4F4),
    onSecondaryContainer: Color(0xFF000000),
    tertiary: Color(0xFF3F2A00),
    onTertiary: Color(0xFFFFEDC2),
    tertiaryContainer: Color(0xFFFFEDC2),
    onTertiaryContainer: Color(0xFF3F2A00),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFBDAD6),
    onErrorContainer: Color(0xFF410E0B),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF000000),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF4F4F4),
    surfaceContainer: Color(0xFFF4F4F4),
    surfaceContainerHigh: Color(0xFFE6E6E6),
    surfaceContainerHighest: Color(0xFFE6E6E6),
    onSurfaceVariant: Color(0xFF4A4A4A),
    outline: Color(0xFF6B6B6B),
    outlineVariant: Color(0xFFDEDEDE),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF000000),
    onInverseSurface: Color(0xFFFFFFFF),
    inversePrimary: Color(0xFFFFFFFF),
    surfaceTint: Color(0xFF000000),
  );

  // ---- Dark ----
  static const ColorScheme _darkScheme = ColorScheme.dark(
    primary: Color(0xFFFFFFFF),
    onPrimary: Color(0xFF000000),
    primaryContainer: Color(0xFF242424),
    onPrimaryContainer: Color(0xFFFFFFFF),
    secondary: Color(0xFFC7C7C7),
    onSecondary: Color(0xFF000000),
    secondaryContainer: Color(0xFF151515),
    onSecondaryContainer: Color(0xFFFFFFFF),
    tertiary: Color(0xFFFFEDC2),
    onTertiary: Color(0xFF3F2A00),
    tertiaryContainer: Color(0xFF3F2A00),
    onTertiaryContainer: Color(0xFFFFEDC2),
    error: Color(0xFFFF8A80),
    onError: Color(0xFF410E0B),
    errorContainer: Color(0xFF410E0B),
    onErrorContainer: Color(0xFFFBDAD6),
    surface: Color(0xFF000000),
    onSurface: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFF000000),
    surfaceContainerLow: Color(0xFF151515),
    surfaceContainer: Color(0xFF151515),
    surfaceContainerHigh: Color(0xFF242424),
    surfaceContainerHighest: Color(0xFF242424),
    onSurfaceVariant: Color(0xFFB3B3B3),
    outline: Color(0xFF7A7A7A),
    outlineVariant: Color(0xFF333333),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFFFFFFF),
    onInverseSurface: Color(0xFF000000),
    inversePrimary: Color(0xFF000000),
    surfaceTint: Color(0xFFFFFFFF),
  );

  static ThemeData light() => _theme(_lightScheme);
  static ThemeData dark() => _theme(_darkScheme);

  static ThemeData _theme(ColorScheme scheme) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: color, width: width),
        );

    final textTheme = Typography.material2021().black.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme.copyWith(
        // Headlines are tight and heavy; times use tabular figures elsewhere.
        displaySmall: textTheme.displaySmall?.copyWith(
          fontSize: 34,
          height: 1.05,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2,
        ),
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontSize: 26,
          height: 1.12,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ),
        headlineMedium: textTheme.headlineMedium?.copyWith(
          fontSize: 28,
          height: 1.1,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontSize: 20,
          height: 1.2,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontSize: 16,
          height: 1.25,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
        bodyMedium: textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.45),
        bodySmall: textTheme.bodySmall?.copyWith(fontSize: 12, height: 1.4),
        labelLarge: textTheme.labelLarge?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        labelMedium: textTheme.labelMedium?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        labelSmall: textTheme.labelSmall?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: 0.3),
        selectionHandleColor: scheme.primary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: scheme.onSurface),
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          color: scheme.onSurface,
        ),
        toolbarHeight: 64,
      ),
      cardTheme: CardThemeData(
        color: cardFillColorOf(scheme),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(
            color: scheme.brightness == Brightness.dark
                ? _cardHairlineDark
                : _cardHairlineLight,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        filled: true,
        fillColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.error)) return scheme.errorContainer;
          if (states.contains(WidgetState.focused)) {
            return scheme.surfaceContainerHighest;
          }
          return scheme.surfaceContainer;
        }),
        // Fields stay borderless until focus or validation needs a clear outline.
        border: border(Colors.transparent, 0),
        enabledBorder: border(Colors.transparent, 0),
        focusedBorder: border(scheme.primary, 2),
        errorBorder: border(scheme.error, 2),
        focusedErrorBorder: border(scheme.error, 2),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        floatingLabelStyle: TextStyle(color: scheme.primary),
        hintStyle: TextStyle(color: placeholderFor(scheme)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.surfaceContainerHigh,
          disabledForegroundColor: disabledForegroundFor(scheme),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
          foregroundColor: scheme.onSurface,
          backgroundColor: scheme.surfaceContainerHigh,
          disabledBackgroundColor: scheme.surfaceContainer,
          disabledForegroundColor: disabledSecondaryForegroundFor(scheme),
          side: BorderSide.none,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chipRadius),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        extendedTextStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 72,
        indicatorColor: scheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        dividerColor: scheme.outlineVariant,
        labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primaryContainer,
        secondarySelectedColor: scheme.primaryContainer,
        disabledColor: scheme.surfaceContainer,
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chipRadius),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.surfaceContainerLowest,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.primary
              : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(scheme.onPrimary),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
        minVerticalPadding: 10,
        iconColor: scheme.onSurfaceVariant,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
        contentTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 14,
          height: 1.45,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(sheetRadius),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.outline,
        dragHandleSize: const Size(40, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(sheetRadius),
          ),
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: scheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(sheetRadius),
        ),
        dayPeriodShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),
    );
  }
}
