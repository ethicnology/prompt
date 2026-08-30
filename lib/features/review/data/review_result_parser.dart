import 'dart:convert';
import '../domain/review_entities.dart';

const reviewResultSchema = <String, dynamic>{
  'type': 'object',
  'additionalProperties': false,
  'required': ['summary', 'findings'],
  'properties': {
    'summary': {'type': 'string'},
    'findings': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': [
          'file',
          'startLine',
          'endLine',
          'side',
          'category',
          'severity',
          'title',
          'description',
          'expectedBehavior',
          'observedBehavior',
          'preconditions',
          'reproduction',
          'impact',
          'evidence',
          'suggestedTest',
          'confidence',
        ],
        'properties': {
          'file': {'type': 'string', 'minLength': 1},
          'startLine': {'type': 'integer', 'minimum': 1},
          'endLine': {'type': 'integer', 'minimum': 1},
          'side': {
            'type': 'string',
            'enum': ['old', 'new'],
          },
          'category': {
            'type': 'string',
            'enum': ['correctness', 'security', 'testsAndRegressions'],
          },
          'severity': {
            'type': 'string',
            'enum': ['info', 'low', 'medium', 'high', 'critical'],
          },
          'title': {'type': 'string'},
          'description': {'type': 'string'},
          'expectedBehavior': {'type': 'string'},
          'observedBehavior': {'type': 'string'},
          'preconditions': {'type': 'string'},
          'reproduction': {'type': 'string'},
          'impact': {'type': 'string'},
          'evidence': {
            'type': 'array',
            'items': {
              'type': 'object',
              'additionalProperties': false,
              'required': ['kind', 'text'],
              'properties': {
                'kind': {
                  'type': 'string',
                  'enum': ['diff', 'documentation', 'test', 'external'],
                },
                'text': {'type': 'string'},
              },
            },
          },
          'suggestedTest': {'type': 'string'},
          'confidence': {'type': 'number', 'minimum': 0, 'maximum': 1},
        },
      },
    },
  },
};

ReviewOpinion parseReviewResult(
  Object value,
  ReviewRole role,
  List<ReviewFile> files,
) {
  final decoded = value is String ? jsonDecode(value) : value;
  if (decoded is! Map ||
      decoded['summary'] is! String ||
      decoded['findings'] is! List) {
    throw const FormatException('Structured review result is malformed.');
  }
  final paths = files.map((file) => file.path).toSet();
  final findings = <ReviewFinding>[];
  for (final raw in decoded['findings'] as List) {
    if (raw is! Map ||
        raw.keys.any(
          (key) =>
              !((reviewResultSchema['properties']!['findings'] as Map)['items']
                      as Map)['properties']
                  .containsKey(key),
        ) ||
        raw['file'] is! String ||
        !paths.contains(raw['file']) ||
        raw['startLine'] is! int ||
        raw['endLine'] is! int ||
        raw['side'] is! String ||
        raw['category'] is! String ||
        raw['severity'] is! String ||
        raw['title'] is! String ||
        raw['description'] is! String ||
        raw['expectedBehavior'] is! String ||
        raw['observedBehavior'] is! String ||
        raw['preconditions'] is! String ||
        raw['reproduction'] is! String ||
        raw['impact'] is! String ||
        raw['evidence'] is! List ||
        raw['suggestedTest'] is! String ||
        raw['confidence'] is! num) {
      throw const FormatException('Structured finding is invalid.');
    }
    final start = raw['startLine'] as int;
    final end = raw['endLine'] as int;
    final confidence = (raw['confidence'] as num).toDouble();
    final categories = ReviewFindingCategory.values.map((e) => e.name);
    final severities = ReviewSeverity.values.map((e) => e.name);
    final source = files.firstWhere((file) => file.path == raw['file']);
    if (start < 1 ||
        end < start ||
        end > _lineLimit(source.patch, raw['side'] as String) ||
        !{'old', 'new'}.contains(raw['side']) ||
        !categories.contains(raw['category']) ||
        !severities.contains(raw['severity']) ||
        confidence < 0 ||
        confidence > 1) {
      throw const FormatException('Structured finding values are invalid.');
    }
    final evidence = <ReviewEvidence>[];
    for (final item in raw['evidence'] as List) {
      if (item is! Map ||
          item.keys.any((key) => key != 'kind' && key != 'text') ||
          item['kind'] is! String ||
          item['text'] is! String ||
          !ReviewEvidenceKind.values
              .map((e) => e.name)
              .contains(item['kind'])) {
        throw const FormatException('Structured evidence is invalid.');
      }
      evidence.add(
        ReviewEvidence(
          kind: ReviewEvidenceKind.values.byName(item['kind'] as String),
          text: item['text'] as String,
        ),
      );
    }
    findings.add(
      ReviewFinding(
        file: raw['file'] as String,
        startLine: start,
        endLine: end,
        side: raw['side'] as String,
        category: ReviewFindingCategory.values.byName(
          raw['category'] as String,
        ),
        severity: ReviewSeverity.values.byName(raw['severity'] as String),
        confidence: confidence,
        title: raw['title'] as String,
        description: raw['description'] as String,
        expectedBehavior: raw['expectedBehavior'] as String,
        observedBehavior: raw['observedBehavior'] as String,
        preconditions: raw['preconditions'] as String,
        reproduction: raw['reproduction'] as String,
        impact: raw['impact'] as String,
        evidence: evidence,
        suggestedTest: raw['suggestedTest'] as String,
      ),
    );
  }
  return ReviewOpinion(
    role: role,
    findings: List.unmodifiable(findings),
    summary: decoded['summary'] as String,
  );
}

int _lineLimit(String patch, String side) {
  var limit = patch.split('\n').length + 1;
  for (final match in RegExp(
    r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@',
  ).allMatches(patch)) {
    final index = side == 'old' ? 1 : 3;
    final start = int.parse(match.group(index)!);
    final count = int.tryParse(match.group(index + 1) ?? '1') ?? 1;
    if (count > 0 && start + count - 1 > limit) limit = start + count - 1;
  }
  return limit;
}
