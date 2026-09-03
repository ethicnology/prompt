import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/diff/diff.dart';

void main() {
  test('parses exact prefixes and both sides line numbers', () {
    final document = UnifiedDiffParser.parse(
      '''diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -2,2 +2,3 @@ void main() {
 context
-old
+new
+added
''',
    );
    final all = document.files.single.rows;
    // Each hunk is introduced by its own header row so a reader can see where
    // lines were skipped.
    expect(all.first.kind, DiffRowKind.meta);
    expect(all.first.content, '@@ -2,2 +2,3 @@ void main() {');

    final rows = all.skip(1).toList();
    expect(rows.map((row) => row.prefix), [' ', '-', '+', '+']);
    expect(rows.map((row) => row.content), ['context', 'old', 'new', 'added']);
    expect(rows[0].oldLine, 2);
    expect(rows[0].newLine, 2);
    expect(rows[1].oldLine, 3);
    expect(rows[1].newLine, isNull);
    expect(rows[2].oldLine, isNull);
    expect(rows[2].newLine, 3);
    expect(rows[3].newLine, 4);
  });

  test('keeps the patch file header out of the displayed rows', () {
    final document = UnifiedDiffParser.parse(
      'diff --git a/lib/a.dart b/lib/a.dart\n'
      'index 1c4e5a7..98e1257 100644\n'
      '--- a/lib/a.dart\n+++ b/lib/a.dart\n'
      '@@ -1 +1 @@\n-old\n+new\n',
    );
    final file = document.files.single;
    // The blob line is still parsed, it just does not take a line of screen.
    expect(
      file.metadata.map((row) => row.content),
      contains('index 1c4e5a7..98e1257 100644'),
    );
    expect(
      file.rows.map((row) => row.content),
      isNot(contains('index 1c4e5a7..98e1257 100644')),
    );
    expect(file.rows.map((row) => row.content), contains('new'));
  });

  test(
    'keeps malformed input displayable and recognizes no-newline metadata',
    () {
      final document = UnifiedDiffParser.parse(
        '--- a/a.txt\n+++ b/a.txt\n@@ -1 +1 @@\n-x\n+y\n\\ No newline at end of file',
      );
      expect(document.files.single.rows.last.kind, DiffRowKind.meta);
      expect(() => UnifiedDiffParser.parse('not a patch\n'), returnsNormally);
    },
  );
}
