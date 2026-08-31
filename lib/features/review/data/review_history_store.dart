import 'dart:async';

import 'package:drift/drift.dart';

import '../../../data/local/prompt_database.dart' as db;
import '../../connection/connection.dart';
import '../../sessions/sessions.dart';
import '../domain/review_entities.dart';

class StoredReviewSummary {
  const StoredReviewSummary({
    required this.id,
    required this.serverProfileId,
    required this.sessionId,
    required this.createdAt,
    required this.state,
    this.fileCount = 0,
    this.passCount = 0,
    this.findingCount = 0,
  });
  final String id;
  final String serverProfileId;
  final String sessionId;
  final DateTime createdAt;
  final ReviewRunState state;
  final int fileCount;
  final int passCount;
  final int findingCount;

  int get reviewerCount => passCount;
  int get hypothesisCount => findingCount;
}

class StoredReview {
  const StoredReview({
    required this.id,
    required this.serverProfileId,
    required this.sessionId,
    required this.createdAt,
    required this.run,
  });
  final String id;
  final String serverProfileId;
  final String sessionId;
  final DateTime createdAt;
  final ReviewRun run;

  StoredReviewSummary get summary => StoredReviewSummary(
    id: id,
    serverProfileId: serverProfileId,
    sessionId: sessionId,
    createdAt: createdAt,
    state: run.state,
    fileCount: run.snapshot?.files.length ?? 0,
    passCount: run.passes.length,
    findingCount: run.passes.fold(
      0,
      (count, pass) => count + (pass.opinion?.findings.length ?? 0),
    ),
  );
}

abstract interface class ReviewHistoryStore {
  Future<void> save(StoredReview review);
  Future<void> replace(StoredReview review);
  Stream<List<StoredReviewSummary>> watchSummaries(
    String serverProfileId,
    String sessionId,
  );
  Future<List<StoredReviewSummary>> listSummaries(
    String serverProfileId,
    String sessionId,
  );
  Future<StoredReview?> load(String id);
  Future<void> delete(String id);
  Future<void> deleteForSessions(
    String serverProfileId,
    Iterable<String> sessionIds,
  );
}

class InMemoryReviewHistoryStore implements ReviewHistoryStore {
  final _reviews = <String, StoredReview>{};
  final _changes = StreamController<void>.broadcast();

  Future<void> close() => _changes.close();

  @override
  Future<void> save(StoredReview review) async {
    _reviews[review.id] = review;
    _changes.add(null);
  }

  @override
  Future<void> replace(StoredReview review) async => save(review);

  @override
  Stream<List<StoredReviewSummary>> watchSummaries(
    String profile,
    String session,
  ) async* {
    yield await listSummaries(profile, session);
    await for (final _ in _changes.stream) {
      yield await listSummaries(profile, session);
    }
  }

  @override
  Future<List<StoredReviewSummary>> listSummaries(
    String profile,
    String session,
  ) async =>
      _reviews.values
          .where(
            (review) =>
                review.serverProfileId == profile &&
                review.sessionId == session,
          )
          .map((review) => review.summary)
          .toList()
        ..sort((a, b) {
          final byDate = b.createdAt.compareTo(a.createdAt);
          return byDate == 0 ? a.id.compareTo(b.id) : byDate;
        });

  @override
  Future<StoredReview?> load(String id) async => _reviews[id];

  @override
  Future<void> delete(String id) async {
    _reviews.remove(id);
    _changes.add(null);
  }

  @override
  Future<void> deleteForSessions(
    String profile,
    Iterable<String> sessions,
  ) async {
    final selected = sessions.toSet();
    _reviews.removeWhere(
      (_, review) =>
          review.serverProfileId == profile &&
          selected.contains(review.sessionId),
    );
    _changes.add(null);
  }
}

class DriftReviewHistoryStore implements ReviewHistoryStore {
  DriftReviewHistoryStore(this._database);
  final db.PromptDatabase _database;

  @override
  Future<void> save(StoredReview review) => replace(review);

  @override
  Future<void> replace(StoredReview review) async {
    await _database.transaction(() async {
      await (_database.delete(
        _database.reviewRuns,
      )..where((row) => row.id.equals(review.id))).go();
      await _writeReview(review);
    });
  }

  Future<void> _writeReview(StoredReview stored) async {
    final run = stored.run;
    final snapshot = run.snapshot;
    await _database
        .into(_database.reviewRuns)
        .insert(
          db.ReviewRunsCompanion.insert(
            id: stored.id,
            serverProfileId: stored.serverProfileId,
            sessionId: stored.sessionId,
            createdAtMillis: stored.createdAt.millisecondsSinceEpoch,
            completedAtMillis: const Value(null),
            state: run.state.name,
            errorType: Value(_failureType(run.error)),
            errorMessage: Value(run.error?.message),
            projectId: Value(snapshot?.target.session.projectId),
            directory: Value(snapshot?.target.session.directory),
            title: Value(snapshot?.target.session.title),
            profileOrigin: Value(snapshot?.target.profile.origin.toString()),
            profileUsername: Value(snapshot?.target.profile.username),
            sessionCreatedAtMillis: Value(
              snapshot?.target.session.createdAt.millisecondsSinceEpoch,
            ),
            sessionUpdatedAtMillis: Value(
              snapshot?.target.session.updatedAt.millisecondsSinceEpoch,
            ),
            parentId: Value(snapshot?.target.session.parentId),
            changedFiles: Value(snapshot?.target.session.changedFiles),
            additions: Value(snapshot?.target.session.additions),
            deletions: Value(snapshot?.target.session.deletions),
            shareUrl: Value(snapshot?.target.session.shareUrl),
            modelProviderId: Value(snapshot?.target.session.modelProviderId),
            modelId: Value(snapshot?.target.session.modelId),
            agentName: Value(snapshot?.target.session.agentName),
          ),
        );
    if (snapshot != null) {
      for (var i = 0; i < snapshot.files.length; i++) {
        final file = snapshot.files[i];
        await _database
            .into(_database.reviewFiles)
            .insert(
              db.ReviewFilesCompanion.insert(
                reviewId: stored.id,
                path: file.path,
                status: file.status,
                patch: file.patch,
              ),
            );
      }
    }
    for (var passIndex = 0; passIndex < run.passes.length; passIndex++) {
      final pass = run.passes[passIndex];
      final passId = '${stored.id}:pass:$passIndex';
      await _database
          .into(_database.reviewPasses)
          .insert(
            db.ReviewPassesCompanion.insert(
              id: passId,
              reviewId: stored.id,
              role: pass.configuration.role.name,
              providerId: pass.configuration.model.providerId,
              modelId: pass.configuration.model.modelId,
              state: pass.state.name,
              childSessionId: Value(pass.childSessionId),
              errorType: Value(_failureType(pass.error)),
              errorMessage: Value(pass.error?.message),
              inputTokens: pass.metrics.inputTokens,
              outputTokens: pass.metrics.outputTokens,
              reasoningTokens: pass.metrics.reasoningTokens,
              cacheTokens: pass.metrics.cacheTokens,
              cost: pass.metrics.cost,
              durationMillis: Value(pass.metrics.duration?.inMilliseconds),
            ),
          );
      final opinion = pass.opinion;
      if (opinion != null) await _writeOpinion(stored.id, passId, opinion);
    }
    for (var i = 0; i < run.disagreements.length; i++) {
      final disagreementId = '${stored.id}:disagreement:$i';
      await _database
          .into(_database.reviewDisagreements)
          .insert(
            db.ReviewDisagreementsCompanion.insert(
              id: disagreementId,
              reviewId: stored.id,
            ),
          );
      for (final source in run.disagreements[i].sources) {
        final findingId = _findingId(
          stored.id,
          run.passes.indexWhere((p) => p.configuration.role == source.role),
          run.passes
              .firstWhere((p) => p.configuration.role == source.role)
              .opinion!
              .findings
              .indexOf(source.finding),
        );
        await _database
            .into(_database.reviewDisagreementSources)
            .insert(
              db.ReviewDisagreementSourcesCompanion.insert(
                disagreementId: disagreementId,
                findingId: findingId,
                role: source.role.name,
              ),
            );
      }
    }
  }

  Future<void> _writeOpinion(
    String reviewId,
    String passId,
    ReviewOpinion opinion,
  ) async {
    final opinionId = '$passId:opinion';
    await _database
        .into(_database.reviewOpinions)
        .insert(
          db.ReviewOpinionsCompanion.insert(
            id: opinionId,
            passId: passId,
            role: opinion.role.name,
            summary: opinion.summary,
          ),
        );
    for (var i = 0; i < opinion.findings.length; i++) {
      final finding = opinion.findings[i];
      final findingId = _findingId(
        reviewId,
        int.parse(passId.split(':').last),
        i,
      );
      await _database
          .into(_database.reviewFindings)
          .insert(
            db.ReviewFindingsCompanion.insert(
              id: findingId,
              opinionId: opinionId,
              file: finding.file,
              startLine: finding.startLine,
              endLine: finding.endLine,
              side: finding.side,
              category: finding.category.name,
              severity: finding.severity.name,
              confidence: finding.confidence,
              title: finding.title,
              description: finding.description,
              expectedBehavior: finding.expectedBehavior,
              observedBehavior: finding.observedBehavior,
              preconditions: finding.preconditions,
              reproduction: finding.reproduction,
              impact: finding.impact,
              suggestedTest: finding.suggestedTest,
            ),
          );
      for (final evidence in finding.evidence) {
        await _database
            .into(_database.reviewEvidenceEntries)
            .insert(
              db.ReviewEvidenceEntriesCompanion.insert(
                findingId: findingId,
                kind: evidence.kind.name,
                evidenceText: evidence.text,
              ),
            );
      }
    }
  }

  @override
  Stream<List<StoredReviewSummary>> watchSummaries(
    String profile,
    String session,
  ) {
    final query = _database.select(_database.reviewRuns)
      ..where(
        (row) =>
            row.serverProfileId.equals(profile) & row.sessionId.equals(session),
      )
      ..orderBy([
        (row) => OrderingTerm.desc(row.createdAtMillis),
        (row) => OrderingTerm.asc(row.id),
      ]);
    return query.watch().asyncMap(_summaries);
  }

  @override
  Future<List<StoredReviewSummary>> listSummaries(
    String profile,
    String session,
  ) async => _summaries(await _summaryRows(profile, session));

  Future<List<db.ReviewRun>> _summaryRows(String profile, String session) =>
      (_database.select(_database.reviewRuns)
            ..where(
              (row) =>
                  row.serverProfileId.equals(profile) &
                  row.sessionId.equals(session),
            )
            ..orderBy([
              (row) => OrderingTerm.desc(row.createdAtMillis),
              (row) => OrderingTerm.asc(row.id),
            ]))
          .get();

  Future<List<StoredReviewSummary>> _summaries(List<db.ReviewRun> rows) async {
    if (rows.isEmpty) return const [];
    final ids = rows.map((row) => row.id).toSet();
    final files = await (_database.select(
      _database.reviewFiles,
    )..where((row) => row.reviewId.isIn(ids))).get();
    final passes = await (_database.select(
      _database.reviewPasses,
    )..where((row) => row.reviewId.isIn(ids))).get();
    final opinions =
        await (_database.select(_database.reviewOpinions)..where(
              (row) => row.passId.isIn(passes.map((pass) => pass.id).toSet()),
            ))
            .get();
    final findings = opinions.isEmpty
        ? const <db.ReviewFinding>[]
        : await (_database.select(_database.reviewFindings)..where(
                (row) => row.opinionId.isIn(opinions.map((o) => o.id).toSet()),
              ))
              .get();
    final fileCounts = <String, int>{};
    final passCounts = <String, int>{};
    final findingCounts = <String, int>{};
    for (final file in files) {
      fileCounts.update(file.reviewId, (count) => count + 1, ifAbsent: () => 1);
    }
    for (final pass in passes) {
      passCounts.update(pass.reviewId, (count) => count + 1, ifAbsent: () => 1);
    }
    final passById = {for (final pass in passes) pass.id: pass.reviewId};
    for (final finding in findings) {
      final passId = opinions
          .firstWhere((o) => o.id == finding.opinionId)
          .passId;
      final reviewId = passById[passId];
      if (reviewId != null) {
        findingCounts.update(reviewId, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    return [
      for (final row in rows)
        StoredReviewSummary(
          id: row.id,
          serverProfileId: row.serverProfileId,
          sessionId: row.sessionId,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            row.createdAtMillis,
            isUtc: true,
          ),
          state: ReviewRunState.values.byName(row.state),
          fileCount: fileCounts[row.id] ?? 0,
          passCount: passCounts[row.id] ?? 0,
          findingCount: findingCounts[row.id] ?? 0,
        ),
    ].toList(growable: false);
  }

  @override
  Future<StoredReview?> load(String id) async {
    final row = await (_database.select(
      _database.reviewRuns,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final files =
        await (_database.select(_database.reviewFiles)
              ..where((r) => r.reviewId.equals(id))
              ..orderBy([(r) => OrderingTerm.asc(r.id)]))
            .get();
    final passes =
        await (_database.select(_database.reviewPasses)
              ..where((r) => r.reviewId.equals(id))
              ..orderBy([(r) => OrderingTerm.asc(r.id)]))
            .get();
    final domainPasses = <ReviewPass>[];
    final findingsById = <String, ReviewFinding>{};
    for (final pass in passes) {
      final opinionRow = await (_database.select(
        _database.reviewOpinions,
      )..where((r) => r.passId.equals(pass.id))).getSingleOrNull();
      ReviewOpinion? opinion;
      if (opinionRow != null) opinion = await _readOpinion(opinionRow);
      final loadedOpinion = opinion;
      for (final finding
          in loadedOpinion?.findings ?? const <ReviewFinding>[]) {
        if (loadedOpinion != null) {
          findingsById[_findingId(
                id,
                int.parse(pass.id.split(':').last),
                loadedOpinion.findings.indexOf(finding),
              )] =
              finding;
        }
      }
      domainPasses.add(
        ReviewPass(
          configuration: ReviewReviewerConfiguration(
            role: ReviewRole.values.byName(pass.role),
            model: ReviewModelConfiguration(
              providerId: pass.providerId,
              modelId: pass.modelId,
            ),
          ),
          state: ReviewPassState.values.byName(pass.state),
          childSessionId: pass.childSessionId,
          opinion: opinion,
          metrics: ReviewPassMetrics(
            inputTokens: pass.inputTokens,
            outputTokens: pass.outputTokens,
            reasoningTokens: pass.reasoningTokens,
            cacheTokens: pass.cacheTokens,
            cost: pass.cost,
            duration: pass.durationMillis == null
                ? null
                : Duration(milliseconds: pass.durationMillis!),
          ),
          error: _failure(pass.errorType, pass.errorMessage),
        ),
      );
    }
    final snapshot = ReviewSnapshot.stored(
      target: ReviewTarget(
        profile: await _databaseProfile(
          row.serverProfileId,
          origin: row.profileOrigin,
          username: row.profileUsername,
        ),
        session: OpenCodeSession(
          id: row.sessionId,
          projectId: row.projectId ?? '',
          directory: row.directory ?? '',
          title: row.title ?? '',
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            row.sessionCreatedAtMillis ?? row.createdAtMillis,
            isUtc: true,
          ),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            row.sessionUpdatedAtMillis ?? row.createdAtMillis,
            isUtc: true,
          ),
          parentId: row.parentId,
          changedFiles: row.changedFiles,
          additions: row.additions,
          deletions: row.deletions,
          shareUrl: row.shareUrl,
          modelProviderId: row.modelProviderId,
          modelId: row.modelId,
          agentName: row.agentName,
        ),
      ),
      files: files
          .map(
            (f) => ReviewFile(path: f.path, status: f.status, patch: f.patch),
          )
          .toList(),
    );
    final disagreementRows =
        await (_database.select(_database.reviewDisagreements)
              ..where((d) => d.reviewId.equals(id))
              ..orderBy([(d) => OrderingTerm.asc(d.id)]))
            .get();
    final disagreements = <ReviewDisagreement>[];
    for (final disagreement in disagreementRows) {
      final sources =
          await (_database.select(_database.reviewDisagreementSources)
                ..where((s) => s.disagreementId.equals(disagreement.id))
                ..orderBy([(s) => OrderingTerm.asc(s.id)]))
              .get();
      disagreements.add(
        ReviewDisagreement(
          sources: [
            for (final source in sources)
              if (findingsById[source.findingId] case final finding?)
                ReviewFindingSource(
                  role: ReviewRole.values.byName(source.role),
                  finding: finding,
                ),
          ],
        ),
      );
    }
    return StoredReview(
      id: row.id,
      serverProfileId: row.serverProfileId,
      sessionId: row.sessionId,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.createdAtMillis,
        isUtc: true,
      ),
      run: ReviewRun(
        state: ReviewRunState.values.byName(row.state),
        snapshot: snapshot,
        passes: domainPasses,
        disagreements: disagreements,
        error: _failure(row.errorType, row.errorMessage),
      ),
    );
  }

  Future<ReviewOpinion> _readOpinion(db.ReviewOpinion row) async {
    final findings =
        await (_database.select(_database.reviewFindings)
              ..where((f) => f.opinionId.equals(row.id))
              ..orderBy([(f) => OrderingTerm.asc(f.id)]))
            .get();
    return ReviewOpinion(
      role: ReviewRole.values.byName(row.role),
      summary: row.summary,
      findings: [
        for (final finding in findings)
          ReviewFinding(
            file: finding.file,
            startLine: finding.startLine,
            endLine: finding.endLine,
            side: finding.side,
            category: ReviewFindingCategory.values.byName(finding.category),
            severity: ReviewSeverity.values.byName(finding.severity),
            confidence: finding.confidence,
            title: finding.title,
            description: finding.description,
            expectedBehavior: finding.expectedBehavior,
            observedBehavior: finding.observedBehavior,
            preconditions: finding.preconditions,
            reproduction: finding.reproduction,
            impact: finding.impact,
            suggestedTest: finding.suggestedTest,
            evidence:
                (await (_database.select(_database.reviewEvidenceEntries)
                          ..where((e) => e.findingId.equals(finding.id))
                          ..orderBy([(e) => OrderingTerm.asc(e.id)]))
                        .get())
                    .map(
                      (e) => ReviewEvidence(
                        kind: ReviewEvidenceKind.values.byName(e.kind),
                        text: e.evidenceText,
                      ),
                    )
                    .toList(growable: false),
          ),
      ],
    );
  }

  Future<ServerProfile> _databaseProfile(
    String id, {
    String? origin,
    String? username,
  }) async {
    final row = await (_database.select(
      _database.serverProfiles,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    final parsedOrigin = Uri.tryParse(origin ?? (row?.origin ?? ''));
    return parsedOrigin == null
        ? ServerProfile(origin: Uri.parse('stored://$id'))
        : ServerProfile(
            origin: parsedOrigin,
            username: username ?? row?.username,
          );
  }

  @override
  Future<void> delete(String id) => (_database.delete(
    _database.reviewRuns,
  )..where((r) => r.id.equals(id))).go();

  @override
  Future<void> deleteForSessions(
    String profile,
    Iterable<String> sessions,
  ) async {
    final ids = sessions.toSet();
    if (ids.isEmpty) return;
    await _database.transaction(
      () async =>
          (_database.delete(_database.reviewRuns)..where(
                (r) =>
                    r.serverProfileId.equals(profile) & r.sessionId.isIn(ids),
              ))
              .go(),
    );
  }
}

String? _failureType(ReviewFailure? failure) => failure?.runtimeType.toString();
ReviewFailure? _failure(String? type, String? message) {
  if (type == null || message == null) return null;
  if (type.contains('Cancelled')) return ReviewCancelledFailure(message);
  if (type.contains('Timeout')) return ReviewTimeoutFailure(message);
  if (type.contains('Validation')) return ReviewValidationFailure(message);
  return ReviewProviderFailure(message);
}

String _findingId(String reviewId, int passIndex, int ordinal) =>
    '$reviewId:pass:$passIndex:f:$ordinal';
