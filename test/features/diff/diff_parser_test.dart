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
    final rows = document.files.single.rows;
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
