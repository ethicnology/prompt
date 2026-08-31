import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/capabilities/domain/open_code_model.dart';
import 'package:prompt/features/review/data/review_cost_estimator.dart';
import 'package:prompt/features/review/domain/review_cost_estimate.dart';

void main() {
  final generatedAt = DateTime.utc(2026, 8, 30);

  OpenCodeModel model(
    String id, {
    double? input,
    OpenCodeModelLimits? limits,
  }) => OpenCodeModel(
    providerId: 'provider',
    id: id,
    name: id,
    isProviderConnected: true,
    pricing: input == null ? null : OpenCodeModelPricing(input: input),
    limits: limits,
  );

  test('uses UTF-8 conservative bounds and includes the full payload', () {
    final estimate = ReviewCostEstimator(clock: () => generatedAt).estimate([
      ReviewCostInput(model: model('one', input: 2), serializedPrompt: 'abcd'),
    ]);

    expect(
      estimate.reviewers.single.precision,
      ReviewTokenPrecision.approximate,
    );
    expect(estimate.reviewers.single.tokenRange.lower, 1);
    expect(estimate.reviewers.single.tokenRange.upper, 4);
    expect(estimate.reviewers.single.inputUsdRange!.lower, 0.000002);
    expect(estimate.reviewers.single.inputUsdRange!.upper, 0.000008);
    expect(estimate.provenance.generatedAt, generatedAt);
    expect(estimate.provenance.unit, contains('UTF-8'));
  });

  test(
    'duplicates reviewers, applies heterogeneous rates, and reports limits',
    () {
      final estimate = ReviewCostEstimator(clock: () => generatedAt).estimate([
        ReviewCostInput(
          model: model(
            'cheap',
            input: 1,
            limits: const OpenCodeModelLimits(input: 2),
          ),
          serializedPrompt: 'abcd',
        ),
        ReviewCostInput(
          model: model(
            'expensive',
            input: 3,
            limits: const OpenCodeModelLimits(context: 3),
          ),
          serializedPrompt: 'abcd',
        ),
        ReviewCostInput(model: model('unknown'), serializedPrompt: 'abcd'),
        ReviewCostInput(
          model: model('cheap', input: 1),
          serializedPrompt: 'abcd',
        ),
      ]);

      expect(estimate.reviewers, hasLength(4));
      expect(estimate.totalTokenRange, isA<ReviewTokenRange>());
      expect(estimate.unavailableModelIds, ['provider/unknown']);
      expect(estimate.totalUsdRange, isNull);
      expect(estimate.theoreticalMinimumInputUsd, isNull);
      expect(estimate.violations.map((violation) => violation.kind), [
        ReviewLimitKind.input,
        ReviewLimitKind.context,
      ]);
    },
  );
}
