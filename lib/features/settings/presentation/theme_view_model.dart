import 'package:flutter/material.dart';

import '../data/theme_preference_store.dart';

class ThemeViewModel extends ValueNotifier<ThemeMode> {
  ThemeViewModel(this._store) : super(ThemeMode.system);

  final ThemePreferenceStore _store;

  Future<void> load() async {
    value = await _store.load();
  }

  Future<void> select(ThemeMode mode) async {
    value = mode;
    await _store.save(mode);
  }
}
