import 'package:flutter/material.dart';

import 'lab_screen.dart';

void main() => runApp(const SttLabApp());

class SttLabApp extends StatelessWidget {
  const SttLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff62e6be),
      brightness: Brightness.dark,
      surface: const Color(0xff0b1114),
    );
    return MaterialApp(
      title: 'STT Lab',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const LabScreen(),
    );
  }
}
