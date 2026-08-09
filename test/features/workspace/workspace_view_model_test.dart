import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/sessions/domain/open_code_project.dart';
import 'package:prompt/features/workspace/data/workspace_repository.dart';
import 'package:prompt/features/workspace/domain/workspace_entry.dart';
import 'package:prompt/features/workspace/domain/workspace_failure.dart';
import 'package:prompt/features/workspace/presentation/workspace_view_model.dart';

void main() {
  final profile = ServerProfile(origin: Uri.parse('http://10.80.0.1:4096'));
  const project = OpenCodeProject(id: 'project', directory: '/work');

  test('discards a stale search response after a newer query', () async {
    final repository = _SearchRepository();
    final viewModel = WorkspaceViewModel(repository);
    addTearDown(viewModel.dispose);
    await viewModel.selectProject(profile, project);

    viewModel.search(profile, WorkspaceSearchKind.file, 'old');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    viewModel.search(profile, WorkspaceSearchKind.file, 'new');
    await Future<void>.delayed(const Duration(milliseconds: 350));

    repository.old.complete(
      const Ok([WorkspaceFileSearchResult(path: 'old.dart')]),
    );
    await Future<void>.delayed(Duration.zero);
    repository.current.complete(
      const Ok([WorkspaceFileSearchResult(path: 'new.dart')]),
    );
    await Future<void>.delayed(Duration.zero);

    final state = viewModel.value as WorkspaceReady;
    final search = state.search as WorkspaceSearchReady;
    expect(search.query, 'new');
    expect(search.results.single.path, 'new.dart');
  });
}

class _SearchRepository implements WorkspaceRepository {
  final old =
      Completer<Result<List<WorkspaceSearchResult>, WorkspaceFailure>>();
  final current =
      Completer<Result<List<WorkspaceSearchResult>, WorkspaceFailure>>();

  @override
  Future<Result<WorkspaceSnapshot, WorkspaceFailure>> load(
    ServerProfile profile,
    String directory,
    String path,
  ) async => const Ok(
    WorkspaceSnapshot(
      entries: [],
      status: [],
      vcs: WorkspaceVcsSummary('main'),
    ),
  );

  @override
  Future<Result<WorkspaceFileContent, WorkspaceFailure>> readFile(
    ServerProfile profile,
    String directory,
    String path,
  ) async => const Ok(WorkspaceFileContent.binary());

  @override
  Future<Result<List<WorkspaceSearchResult>, WorkspaceFailure>> search(
    ServerProfile profile,
    String directory,
    WorkspaceSearchKind kind,
    String query,
  ) => query == 'old' ? old.future : current.future;
}
