import 'package:flutter/material.dart';

/// Semantic surfaces shared by the conversation, workspace, and diagnostics.
///
/// Keeping these tokens separate from Material's generic containers prevents
/// unrelated screens from drifting apart as the product grows.
@immutable
class PromptTokens extends ThemeExtension<PromptTokens> {
  const PromptTokens({
    required this.panel,
    required this.panelRaised,
    required this.subtle,
    required this.success,
    required this.warning,
    required this.danger,
    required this.diffAdd,
    required this.diffDelete,
  });

  final Color panel;
  final Color panelRaised;
  final Color subtle;
  final Color success;
  final Color warning;
  final Color danger;
  final Color diffAdd;
  final Color diffDelete;

  @override
  PromptTokens copyWith({
    Color? panel,
    Color? panelRaised,
    Color? subtle,
    Color? success,
    Color? warning,
    Color? danger,
    Color? diffAdd,
    Color? diffDelete,
  }) => PromptTokens(
    panel: panel ?? this.panel,
    panelRaised: panelRaised ?? this.panelRaised,
    subtle: subtle ?? this.subtle,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    diffAdd: diffAdd ?? this.diffAdd,
    diffDelete: diffDelete ?? this.diffDelete,
  );

  @override
  PromptTokens lerp(PromptTokens? other, double t) {
    if (other == null) return this;
    return PromptTokens(
      panel: Color.lerp(panel, other.panel, t)!,
      panelRaised: Color.lerp(panelRaised, other.panelRaised, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      diffAdd: Color.lerp(diffAdd, other.diffAdd, t)!,
      diffDelete: Color.lerp(diffDelete, other.diffDelete, t)!,
    );
  }
}

ThemeData promptTheme() => _theme(Brightness.light);

ThemeData promptDarkTheme() => _theme(Brightness.dark);

ThemeData _theme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff56d6b2),
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    surface: dark ? const Color(0xff0d1115) : const Color(0xfff5f7f6),
  );
  final textTheme = ThemeData(brightness: brightness).textTheme.copyWith(
    headlineSmall: const TextStyle(
      fontSize: 24,
      height: 1.15,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
    ),
    titleLarge: const TextStyle(
      fontSize: 19,
      height: 1.15,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.6,
    ),
    titleMedium: const TextStyle(
      fontSize: 16,
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    ),
    bodyLarge: const TextStyle(fontSize: 16, height: 1.48),
    bodyMedium: const TextStyle(fontSize: 14, height: 1.45),
    bodySmall: const TextStyle(fontSize: 12.5, height: 1.4),
    labelLarge: const TextStyle(fontWeight: FontWeight.w600),
  );

  final rounded = OutlineInputBorder(
    borderRadius: BorderRadius.circular(13),
    borderSide: BorderSide(color: scheme.outlineVariant),
  );
  final tokens = PromptTokens(
    panel: dark ? const Color(0xff12181d) : const Color(0xffffffff),
    panelRaised: dark ? const Color(0xff1a2229) : const Color(0xfff0f3f1),
    subtle: dark ? const Color(0xff93a2aa) : const Color(0xff59676c),
    success: dark ? const Color(0xff77d6b7) : const Color(0xff13795b),
    warning: dark ? const Color(0xffffc985) : const Color(0xff9a5600),
    danger: dark ? const Color(0xffffaaa5) : const Color(0xffb42318),
    diffAdd: dark ? const Color(0xff123d30) : const Color(0xffdcf8e9),
    diffDelete: dark ? const Color(0xff4a2225) : const Color(0xffffe5e4),
  );

  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    extensions: [tokens],
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: textTheme,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xff171d22) : const Color(0xffffffff),
      border: rounded,
      enabledBorder: rounded,
      focusedBorder: rounded.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(color: scheme.outlineVariant),
      selectedColor: scheme.primaryContainer,
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: dark ? const Color(0xff252d34) : const Color(0xff20272c),
      contentTextStyle: const TextStyle(color: Colors.white),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: dark ? const Color(0xff171d22) : Colors.white,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: dark ? const Color(0xff171d22) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );
}
