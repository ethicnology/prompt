import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/async/reconnect_backoff.dart';

void main() {
  group('shouldRetry', () {
    test('permits every attempt up to maxAttempts and stops after', () {
      const policy = ReconnectBackoffPolicy(maxAttempts: 3);

      expect(policy.shouldRetry(1), isTrue);
      expect(policy.shouldRetry(2), isTrue);
      expect(policy.shouldRetry(3), isTrue);
      expect(policy.shouldRetry(4), isFalse);
      expect(policy.shouldRetry(100), isFalse);
    });
  });

  group('delayForAttempt', () {
    test('doubles the base delay for each successive attempt', () {
      const policy = ReconnectBackoffPolicy(
        initialDelay: Duration(seconds: 1),
        maxDelay: Duration(minutes: 5),
        jitterFraction: 0, // isolates the exponential growth from jitter
      );
      final random = Random(1);

      expect(policy.delayForAttempt(1, random), const Duration(seconds: 1));
      expect(policy.delayForAttempt(2, random), const Duration(seconds: 2));
      expect(policy.delayForAttempt(3, random), const Duration(seconds: 4));
      expect(policy.delayForAttempt(4, random), const Duration(seconds: 8));
    });

    test('never exceeds maxDelay even after many attempts', () {
      const policy = ReconnectBackoffPolicy(
        initialDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 30),
        maxAttempts: 20,
        jitterFraction: 0,
      );
      final random = Random(2);

      final delay = policy.delayForAttempt(20, random);

      expect(delay, const Duration(seconds: 30));
    });

    test('adds up to jitterFraction extra on top of the base delay', () {
      const policy = ReconnectBackoffPolicy(
        initialDelay: Duration(seconds: 10),
        maxDelay: Duration(minutes: 5),
        jitterFraction: 0.5,
      );

      // A broad sample of seeds must always land within
      // [base, base * 1.5]; jitter must never make the delay shrink below
      // the deterministic base, nor exceed its declared bound.
      for (var seed = 0; seed < 50; seed++) {
        final delay = policy.delayForAttempt(1, Random(seed));
        expect(delay.inMilliseconds, greaterThanOrEqualTo(10000));
        expect(delay.inMilliseconds, lessThanOrEqualTo(15000));
      }
    });

    test('jittered delay still respects maxDelay at the cap', () {
      const policy = ReconnectBackoffPolicy(
        initialDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 30),
        maxAttempts: 20,
        jitterFraction: 0.5,
      );

      for (var seed = 0; seed < 50; seed++) {
        final delay = policy.delayForAttempt(10, Random(seed));
        expect(delay.inSeconds, lessThanOrEqualTo(30));
      }
    });
  });
}
