import 'package:flutter/material.dart';

ThemeData promptTheme() {
  return _theme(Brightness.light);
}

ThemeData promptDarkTheme() {
  return _theme(Brightness.dark);
}

ThemeData _theme(Brightness brightness) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff5e5ce6),
    brightness: brightness,
  );

  return ThemeData(
    brightness: brightness,
    colorScheme: colorScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: brightness == Brightness.dark
        ? const Color(0xff111113)
        : const Color(0xfffbf9fc),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: brightness == Brightness.dark
          ? const Color(0xff1c1b1f)
          : const Color(0xfff1eff4),
      border: const OutlineInputBorder(),
    ),
  );
}
