import '../../capabilities/capabilities.dart';

enum ReviewTokenPrecision { exact, approximate, unavailable }

enum ReviewLimitKind { input, context }

class ReviewTokenRange {
  const ReviewTokenRange({required this.lower, required this.upper});
  final int lower;
  final int upper;
}

class ReviewEstimateProvenance {
  const ReviewEstimateProvenance({
    required this.source,
    required this.generatedAt,
    this.unit = 'UTF-8 bytes; conservative token approximation',
    this.currency = 'USD per million tokens',
  });
  final String source;
  final DateTime generatedAt;
  final String unit;
  final String currency;
}

class ReviewLimitViolation {
  const ReviewLimitViolation({
    required this.modelId,
    required this.kind,
    required this.estimatedUpperBound,
    required this.limit,
  });
  final String modelId;
  final ReviewLimitKind kind;
  final int estimatedUpperBound;
  final int limit;
}

class ReviewReviewerEstimate {
  const ReviewReviewerEstimate({
    required this.modelId,
    required this.tokenRange,
    required this.precision,
    required this.inputUsdRange,
    required this.priceKnown,
  });
  final String modelId;
  final ReviewTokenRange tokenRange;
  final ReviewTokenPrecision precision;
  final ReviewUsdRange? inputUsdRange;
  final bool priceKnown;
}

class ReviewUsdRange {
  const ReviewUsdRange({required this.lower, required this.upper});
  final double lower;
  final double upper;
}

class ReviewCostEstimate {
  const ReviewCostEstimate({
    required this.reviewers,
    required this.totalTokenRange,
    required this.totalUsdRange,
    required this.theoreticalMinimumInputUsd,
    required this.unavailableModelIds,
    required this.violations,
    required this.provenance,
  });
  final List<ReviewReviewerEstimate> reviewers;
  final ReviewTokenRange totalTokenRange;
  final ReviewUsdRange? totalUsdRange;
  final double? theoreticalMinimumInputUsd;
  final List<String> unavailableModelIds;
  final List<ReviewLimitViolation> violations;
  final ReviewEstimateProvenance provenance;
}

/// Typed helper retained here so estimate consumers need not inspect model data.
double? inputUsdPerMillion(OpenCodeModel model) => model.pricing?.input;
