import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/app/prompt_app.dart';
import 'package:prompt/features/settings/data/theme_preference_store.dart';

void main() {
  testWidgets('shows the private server connection form', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(PromptApp(lastProfileLoader: () async => null));

    expect(find.text('Connect Prompt'), findsOneWidget);
    expect(find.text('Private server address'), findsOneWidget);
    expect(find.text('Test private connection'), findsOneWidget);
  });

  testWidgets('restores a persisted dark theme at startup', (tester) async {
    await tester.pumpWidget(
      PromptApp(
        lastProfileLoader: () async => null,
        themePreferenceStore: InMemoryThemePreferenceStore(ThemeMode.dark),
      ),
    );
    await tester.pump();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });
}
