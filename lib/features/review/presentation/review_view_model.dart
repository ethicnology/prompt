import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/review_repository.dart';
import '../domain/review_entities.dart';

class ReviewViewModel extends ValueNotifier<ReviewRun> {
  ReviewViewModel(this.repository)
    : super(const ReviewRun(state: ReviewRunState.idle)) {
    _progressSubscription = repository.progress.listen((snapshot) {
      if (!_disposed) value = snapshot;
    });
  }
  final ReviewRepository repository;
  late final StreamSubscription<ReviewRun> _progressSubscription;
  bool _disposed = false;

  Future<void> loadSnapshot(ReviewTarget target) async {
    if (_disposed) return;
    value = ReviewRun(state: ReviewRunState.loading);
    try {
      final snapshot = await repository.loadSnapshot(target);
      if (_disposed) return;
      value = ReviewRun(state: ReviewRunState.idle, snapshot: snapshot);
    } on ReviewValidationException catch (error) {
      if (_disposed) return;
      value = ReviewRun(
        state: ReviewRunState.failed,
        error: ReviewValidationFailure(error.message),
      );
    } on Object catch (_) {
      if (!_disposed) {
        value = const ReviewRun(
          state: ReviewRunState.failed,
          error: ReviewProviderFailure('Unable to load the session diff.'),
        );
      }
    }
  }

  Future<void> start(
    ReviewTarget target,
    List<ReviewReviewerConfiguration> configurations,
  ) async {
    if (_disposed) return;
    value = ReviewRun(state: ReviewRunState.running);
    try {
      final result = await repository.start(target, configurations);
      if (!_disposed) value = result;
    } on ReviewValidationException catch (error) {
      value = ReviewRun(
        state: ReviewRunState.failed,
        error: ReviewValidationFailure(error.message),
      );
    } on Object catch (_) {
      if (!_disposed) {
        value = const ReviewRun(
          state: ReviewRunState.failed,
          error: ReviewProviderFailure('Review could not be completed.'),
        );
      }
    }
  }

  Future<void> cancel() async {
    await repository.cancel();
    if (!_disposed) value = value.copyWith(state: ReviewRunState.cancelled);
  }

  @override
  void dispose() {
    _disposed = true;
    _progressSubscription.cancel();
    unawaited(repository.dispose());
    super.dispose();
  }
}
