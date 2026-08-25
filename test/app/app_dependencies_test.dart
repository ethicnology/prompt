import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/app/app_dependencies.dart';
import 'package:prompt/data/local/prompt_local_storage_handle.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/queue/queue.dart';
import 'package:prompt/features/settings/settings.dart';

void main() {
  test('composition accepts an injected lazy storage backend', () async {
    final serverProfiles = InMemoryServerProfileStore();
    final queuedPrompts = InMemoryQueuePromptsDao();
    var opens = 0;
    final dependencies = AppDependencies.create(
      themePreferenceStore: InMemoryThemePreferenceStore(ThemeMode.dark),
      openStorage: () async {
        opens++;
        return PromptLocalStorageHandle(
          serverProfiles: serverProfiles,
          queuedPrompts: queuedPrompts,
          closeHandle: () async {},
        );
      },
    );

    expect(await dependencies.ensureStorage(), isA<PromptLocalStorageHandle>());
    expect(
      await dependencies.ensureStorage(),
      same(await dependencies.ensureStorage()),
    );
    expect(opens, 1);

    await dependencies.dispose();
  });

  test(
    'concurrent storage initialization opens the backend only once',
    () async {
      final opened = Completer<PromptLocalStorageHandle>();
      var opens = 0;
      final dependencies = AppDependencies.create(
        themePreferenceStore: InMemoryThemePreferenceStore(ThemeMode.dark),
        openStorage: () {
          opens++;
          return opened.future;
        },
      );

      final first = dependencies.ensureStorage();
      final second = dependencies.ensureStorage();
      await Future<void>.delayed(Duration.zero);
      expect(opens, 1);

      opened.complete(
        PromptLocalStorageHandle(
          serverProfiles: InMemoryServerProfileStore(),
          queuedPrompts: InMemoryQueuePromptsDao(),
          closeHandle: () async {},
        ),
      );
      expect(await first, same(await second));
      await dependencies.dispose();
    },
  );

  test('failed storage initialization can be retried', () async {
    var opens = 0;
    final dependencies = AppDependencies.create(
      themePreferenceStore: InMemoryThemePreferenceStore(ThemeMode.dark),
      openStorage: () async {
        opens++;
        if (opens == 1) {
          throw StateError('open failed');
        }
        return PromptLocalStorageHandle(
          serverProfiles: InMemoryServerProfileStore(),
          queuedPrompts: InMemoryQueuePromptsDao(),
          closeHandle: () async {},
        );
      },
    );

    await expectLater(dependencies.ensureStorage(), throwsStateError);
    expect(await dependencies.ensureStorage(), isA<PromptLocalStorageHandle>());
    expect(opens, 2);
    await dependencies.dispose();
  });

  test(
    'disposal closes storage that finishes opening after disposal starts',
    () async {
      final opened = Completer<PromptLocalStorageHandle>();
      var closes = 0;
      final dependencies = AppDependencies.create(
        themePreferenceStore: InMemoryThemePreferenceStore(ThemeMode.dark),
        openStorage: () => opened.future,
      );

      final pending = dependencies.ensureStorage();
      final disposing = dependencies.dispose();
      await Future<void>.delayed(Duration.zero);
      opened.complete(
        PromptLocalStorageHandle(
          serverProfiles: InMemoryServerProfileStore(),
          queuedPrompts: InMemoryQueuePromptsDao(),
          closeHandle: () async => closes++,
        ),
      );

      await expectLater(pending, throwsStateError);
      await disposing;
      expect(closes, 1);
    },
  );

  test('concurrent queue initialization creates one coordinator', () async {
    final opened = Completer<PromptLocalStorageHandle>();
    final dependencies = AppDependencies.create(
      themePreferenceStore: InMemoryThemePreferenceStore(ThemeMode.dark),
      openStorage: () => opened.future,
    );

    final first = dependencies.ensureQueueCoordinator();
    final second = dependencies.ensureQueueCoordinator();
    opened.complete(
      PromptLocalStorageHandle(
        serverProfiles: InMemoryServerProfileStore(),
        queuedPrompts: InMemoryQueuePromptsDao(),
        closeHandle: () async {},
      ),
    );

    expect(await first, same(await second));
    await dependencies.dispose();
  });
}
