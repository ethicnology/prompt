import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/features/review/data/review_repository.dart';
import 'package:prompt/features/review/domain/review_entities.dart';
import 'package:prompt/features/review/presentation/review_view_model.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';

class _Repository implements ReviewRepository {
  _Repository(this.snapshotFuture);
  final Future<ReviewSnapshot> snapshotFuture;
  final progressController = StreamController<ReviewRun>.broadcast();
  var cancelCalls = 0;
  var disposeCalls = 0;
  @override
  Stream<ReviewRun> get progress => progressController.stream;
  @override
  Future<ReviewSnapshot> loadSnapshot(ReviewTarget target) => snapshotFuture;
  @override
  Future<ReviewRun> start(
    ReviewTarget target,
    List<ReviewReviewerConfiguration> configurations, {
    Duration timeout = const Duration(seconds: 120),
    Duration globalTimeout = const Duration(seconds: 240),
  }) async => throw UnimplementedError();
  @override
  Future<void> cancel() async => cancelCalls++;
  @override
  Future<void> dispose() async {
    disposeCalls++;
    await progressController.close();
  }
}

void main() {
  final snapshot = ReviewSnapshot(
    target: ReviewTarget(
      profile: ServerProfile(origin: Uri.parse('http://10.0.0.1')),
      session: OpenCodeSession(
        id: 's',
        projectId: 'p',
        directory: '/w',
        title: 's',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ),
    files: const [ReviewFile(path: 'a', status: 'M', patch: 'x')],
  );

  test(
    'cancel preserves the current run data while changing only run state',
    () async {
      final repository = _Repository(Future.value(snapshot));
      final viewModel = ReviewViewModel(repository);
      final pass = ReviewPass(
        configuration: const ReviewReviewerConfiguration(
          role: ReviewRole.security,
          model: ReviewModelConfiguration(providerId: 'p', modelId: 'm'),
        ),
        state: ReviewPassState.succeeded,
      );
      final run = ReviewRun(
        state: ReviewRunState.running,
        snapshot: snapshot,
        passes: [pass],
        disagreements: [const ReviewDisagreement(sources: [])],
      );
      viewModel.value = run;
      await viewModel.cancel();
      expect(viewModel.value.state, ReviewRunState.cancelled);
      expect(viewModel.value.snapshot, same(snapshot));
      expect(viewModel.value.passes, same(run.passes));
      expect(viewModel.value.disagreements, same(run.disagreements));
      viewModel.dispose();
    },
  );

  test('loadSnapshot does not notify after disposal', () async {
    final completer = Completer<ReviewSnapshot>();
    final repository = _Repository(completer.future);
    final viewModel = ReviewViewModel(repository);
    viewModel.loadSnapshot(snapshot.target);
    viewModel.dispose();
    completer.complete(snapshot);
    await Future<void>.delayed(Duration.zero);
    expect(repository.disposeCalls, 1);
  });
}
