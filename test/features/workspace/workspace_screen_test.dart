import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/sessions/domain/open_code_project.dart';
import 'package:prompt/features/workspace/data/workspace_repository.dart';
import 'package:prompt/features/workspace/domain/workspace_entry.dart';
import 'package:prompt/features/workspace/domain/workspace_failure.dart';
import 'package:prompt/features/workspace/presentation/workspace_screen.dart';
import 'package:prompt/features/workspace/presentation/workspace_view_model.dart';

void main() {
  testWidgets('requires project selection and displays read-only content', (
    tester,
  ) async {
    final viewModel = WorkspaceViewModel(_Repository());
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceScreen(
          profile: ServerProfile(origin: Uri.parse('http://10.80.0.1:4096')),
          projects: const [OpenCodeProject(id: 'project', directory: '/work')],
          viewModel: viewModel,
        ),
      ),
    );

    expect(
      find.text('Select a server project to browse files.'),
      findsOneWidget,
    );
    await tester.tap(find.byType(DropdownButtonFormField<OpenCodeProject>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('work').last);
    await tester.pumpAndSettle();
    expect(find.text('readme.md'), findsOneWidget);

    await tester.tap(find.text('readme.md'));
    await tester.pumpAndSettle();
    expect(find.text('read-only text'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);
  });
}

class _Repository implements WorkspaceRepository {
  @override
  Future<Result<WorkspaceSnapshot, WorkspaceFailure>> load(
    ServerProfile profile,
    String directory,
    String path,
  ) async => Ok(
    WorkspaceSnapshot(
      entries: const [
        WorkspaceEntry(
          name: 'readme.md',
          path: '/work/readme.md',
          isDirectory: false,
          isIgnored: false,
        ),
      ],
      status: const [],
      vcs: const WorkspaceVcsSummary('main'),
    ),
  );

  @override
  Future<Result<WorkspaceFileContent, WorkspaceFailure>> readFile(
    ServerProfile profile,
    String directory,
    String path,
  ) async => const Ok(WorkspaceFileContent.text('read-only text'));

  @override
  Future<Result<List<WorkspaceSearchResult>, WorkspaceFailure>> search(
    ServerProfile profile,
    String directory,
    WorkspaceSearchKind kind,
    String query,
  ) async => const Ok([]);
}
