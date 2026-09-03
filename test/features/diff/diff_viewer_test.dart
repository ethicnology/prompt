import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/diff/diff.dart';

void main() {
  final document = UnifiedDiffParser.parse('''diff --git a/a.dart b/a.dart
--- a/a.dart
+++ b/a.dart
@@ -1,2 +1,3 @@
-final oldValue = 1;
+final newValue = 2; // changed
 context
+extra
''');

  testWidgets('composes several files whose patches carry their own headers', (
    tester,
  ) async {
    // A review composes one parsed document per file, and a real server patch
    // opens with its own `diff --git` header.
    const first =
        'diff --git a/lib/a.dart b/lib/a.dart\n'
        '--- a/lib/a.dart\n+++ b/lib/a.dart\n@@ -1 +1 @@\n-old\n+new\n';
    const second =
        'diff --git a/lib/b.dart b/lib/b.dart\n'
        '--- a/lib/b.dart\n+++ b/lib/b.dart\n@@ -1 +1 @@\n-old2\n+new2\n';
    final composed = DiffDocument(
      files: [
        ...UnifiedDiffParser.parseFile('lib/a.dart', first).files,
        ...UnifiedDiffParser.parseFile('lib/b.dart', second).files,
      ],
    );

    expect(composed.files, hasLength(2));
    expect(composed.files.map((file) => file.id).toSet(), hasLength(2));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DiffViewer(document: composed)),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('lib/a.dart'), findsOneWidget);
    expect(find.text('lib/b.dart'), findsOneWidget);
  });

  testWidgets(
    'renders lazy rows, semantic controls, backgrounds, and wraps one line',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: DiffViewer(document: document)),
      );
      expect(find.byKey(const ValueKey('diff-file-file-1')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('diff-wrap-file-1-row-1')),
        findsOneWidget,
      );
      expect(find.byTooltip('Wrap line'), findsWidgets);
      expect(find.text('final newValue = 2; // changed'), findsOneWidget);
      final deletionBackground = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('diff-row-background-file-1-row-0')),
      );
      final additionBackground = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('diff-row-background-file-1-row-1')),
      );
      expect(
        (deletionBackground.decoration as BoxDecoration).color,
        isNot(Colors.transparent),
      );
      expect(
        (additionBackground.decoration as BoxDecoration).color,
        isNot(Colors.transparent),
      );
      expect(
        tester
            .widgetList<SingleChildScrollView>(
              find.byType(SingleChildScrollView),
            )
            .any((scroll) => scroll.scrollDirection == Axis.horizontal),
        isTrue,
      );
      final surface = tester.widget<InkWell>(
        find.byKey(const ValueKey('diff-row-surface-file-1-row-1')),
      );
      expect(surface.onTap, isNotNull);
      await tester.tap(find.byKey(const ValueKey('diff-wrap-file-1-row-1')));
      await tester.pump();
      expect(find.byTooltip('Unwrap line'), findsOneWidget);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('diff-file-toggle-file-1')),
        ),
        isNotNull,
      );
    },
  );

  testWidgets('collapses and expands a file and survives a narrow viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(180, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: DiffViewer(document: document)));
    await tester.tap(find.byTooltip('Collapse file'));
    await tester.pump();
    expect(find.text('final newValue = 2; // changed'), findsNothing);
    expect(find.byTooltip('Expand file'), findsOneWidget);
    await tester.tap(find.byTooltip('Expand file'));
    await tester.pump();
    expect(find.text('final newValue = 2; // changed'), findsOneWidget);
  });

  testWidgets('unknown extensions use safe plain rendering', (tester) async {
    final unknown = UnifiedDiffParser.parse(
      '--- a/data.bin\n+++ b/data.bin\n@@ -1 +1 @@\n-a\n+b',
    );
    await tester.pumpWidget(MaterialApp(home: DiffViewer(document: unknown)));
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('does not eagerly construct rows outside the viewport', (
    tester,
  ) async {
    final large = UnifiedDiffParser.parse(
      '@@ -1,1000 +1,1000 @@\n${List.generate(1000, (i) => ' line $i').join('\n')}',
    );
    await tester.pumpWidget(MaterialApp(home: DiffViewer(document: large)));
    expect(find.text('line 999'), findsNothing);
  });
}
