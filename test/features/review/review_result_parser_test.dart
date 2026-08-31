import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/review/review.dart';
import 'package:prompt/features/connection/connection.dart';
import 'package:prompt/features/sessions/sessions.dart';

ReviewFile file() => const ReviewFile(
  path: 'lib/app.dart',
  status: 'modified',
  patch: '@@ -1 +1 @@\n-old\n+new',
);

Map<String, dynamic> result({List<Object?> findings = const []}) => {
  'summary': 'hypotheses',
  'findings': findings,
};

Map<String, dynamic> finding({
  Object? fileName = 'lib/app.dart',
  Object? start = 1,
  Object? end = 1,
  Object? side = 'new',
  Object? category = 'correctness',
  Object? severity = 'medium',
  Object? confidence = .8,
  Object? evidence = const [
    {'kind': 'diff', 'text': 'changed'},
  ],
}) => {
  'file': fileName,
  'startLine': start,
  'endLine': end,
  'side': side,
  'category': category,
  'severity': severity,
  'confidence': confidence,
  'title': 'Issue',
  'description': 'Hypothesis',
  'expectedBehavior': 'Expected',
  'observedBehavior': 'Observed',
  'preconditions': 'None',
  'reproduction': 'Run test',
  'impact': 'Impact',
  'evidence': evidence,
  'suggestedTest': 'Add test',
};

void main() {
  test('accepts a valid structured opinion and preserves hypothesis data', () {
    final opinion = parseReviewResult(
      result(findings: [finding()]),
      ReviewRole.correctness,
      [file()],
    );
    expect(opinion.findings.single.file, 'lib/app.dart');
    expect(opinion.findings.single.confidence, .8);
    expect(
      opinion.findings.single.evidence.single.kind,
      ReviewEvidenceKind.diff,
    );
  });

  test('rejects invalid anchors, ranges, enums, and confidence', () {
    for (final bad in [
      finding(fileName: 'missing.dart'),
      finding(start: 0),
      finding(end: 0),
      finding(side: 'middle'),
      finding(category: 'style'),
      finding(severity: 'blocker'),
      finding(confidence: 2),
      finding(
        evidence: [
          {'kind': 'claim', 'text': 'x'},
        ],
      ),
    ]) {
      expect(
        () => parseReviewResult(result(findings: [bad]), ReviewRole.security, [
          file(),
        ]),
        throwsFormatException,
      );
    }
  });

  test('accepts no findings', () {
    expect(
      parseReviewResult(result(), ReviewRole.testsAndRegressions, [
        file(),
      ]).findings,
      isEmpty,
    );
  });

  test('rejects truncated or malformed structured output', () {
    expect(
      () => parseReviewResult(
        '{"summary":"unfinished"',
        ReviewRole.correctness,
        [file()],
      ),
      throwsFormatException,
    );
    expect(
      () => parseReviewResult(
        {'summary': 'x', 'findings': 'not-list'},
        ReviewRole.correctness,
        [file()],
      ),
      throwsFormatException,
    );
  });

  test('bounds snapshots before any review execution', () {
    final target = ReviewTarget(
      profile: ServerProfile(origin: Uri.parse('http://192.168.1.2')),
      session: OpenCodeSession(
        id: 's',
        projectId: 'p',
        directory: '/workspace',
        title: 's',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    expect(
      () => ReviewSnapshot(target: target, files: const []),
      throwsA(isA<ReviewValidationException>()),
    );
    expect(
      ReviewSnapshot(
        target: target,
        files: List.generate(21, (_) => file()),
      ).files.length,
      21,
    );
    expect(
      ReviewSnapshot(
        target: target,
        files: [ReviewFile(path: 'x', status: 'modified', patch: 'x' * 200001)],
      ).files.single.patch.length,
      200001,
    );
  });
}
