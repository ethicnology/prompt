import 'package:flutter_test/flutter_test.dart';
import 'package:stt_lab/lab_models.dart';

void main() {
  test('word error rate counts substitutions, insertions, and deletions', () {
    expect(
      calculateWordErrorRate('one two three', 'one too'),
      closeTo(2 / 3, 0.001),
    );
    expect(calculateWordErrorRate('Bonjour monde', 'bonjour monde'), 0);
  });

  test('revision count ignores a newly appended suffix', () {
    expect(revisedWordCount('the quick', 'the quick fox'), 0);
    expect(revisedWordCount('the quick fox', 'the quiet fox'), 2);
  });

  test('metrics keep live quality separate from the final decode', () {
    final tracker = MetricsTracker()..start();
    tracker.add(const TranscriptUpdate(confirmed: 'one too', provisional: ''));
    tracker.add(
      const TranscriptUpdate(
        confirmed: 'one two three',
        provisional: '',
        isFinal: true,
      ),
    );

    final metrics = tracker.finish('one two three', 'one two three');

    expect(metrics.streamingWordErrorRate, closeTo(2 / 3, 0.001));
    expect(metrics.wordErrorRate, 0);
  });
}
