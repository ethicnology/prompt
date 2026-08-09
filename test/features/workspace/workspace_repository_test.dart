import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/workspace/data/opencode_workspace_service.dart';
import 'package:prompt/features/workspace/data/workspace_repository.dart';
import 'package:prompt/features/workspace/domain/workspace_entry.dart';
import 'package:prompt/features/workspace/domain/workspace_failure.dart';

void main() {
  final profile = ServerProfile(
    origin: Uri.parse('http://10.80.0.1:4096'),
    username: 'opencode',
  );

  test('loads a selected directory with file status and VCS summary', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return switch (request.url.path) {
        '/file' => http.Response(
          '[{"name":"lib","path":"lib","absolute":"/work/lib",'
          '"type":"directory","ignored":false}]',
          200,
        ),
        '/file/status' => http.Response(
          '[{"path":"lib/main.dart","added":2,"removed":1,'
          '"status":"modified"}]',
          200,
        ),
        '/vcs' => http.Response('{"branch":"main"}', 200),
        _ => http.Response('', 404),
      };
    });
    final repository = OpenCodeWorkspaceRepository(
      OpenCodeWorkspaceService(OpenCodeTransport(client)),
      const _PasswordStore('secret'),
    );

    final result = await repository.load(profile, '/work', '/work');

    expect(result, isA<Ok<WorkspaceSnapshot, WorkspaceFailure>>());
    final snapshot = (result as Ok<WorkspaceSnapshot, WorkspaceFailure>).value;
    expect(snapshot.entries.single.path, '/work/lib');
    expect(snapshot.status.single.status, WorkspaceFileStatus.modified);
    expect(snapshot.vcs.branch, 'main');
    for (final request in requests) {
      expect(request.url.queryParameters['directory'], '/work');
    }
    expect(
      requests
          .singleWhere((request) => request.url.path == '/file')
          .url
          .queryParameters['path'],
      '/work',
    );
  });

  test(
    'reads text content and maps malformed responses to a typed failure',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/file/content');
        expect(request.url.queryParameters['directory'], '/work');
        expect(request.url.queryParameters['path'], '/work/readme.md');
        return http.Response('{"type":"text","content":"hello"}', 200);
      });
      final repository = OpenCodeWorkspaceRepository(
        OpenCodeWorkspaceService(OpenCodeTransport(client)),
        const _PasswordStore(null),
      );

      final result = await repository.readFile(
        profile,
        '/work',
        '/work/readme.md',
      );

      expect(result, isA<Ok<WorkspaceFileContent, WorkspaceFailure>>());
      expect(
        (result as Ok<WorkspaceFileContent, WorkspaceFailure>).value.value,
        'hello',
      );
    },
  );

  test('searches text, files, and symbols in the selected directory', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['directory'], '/work/lib');
      return switch (request.url.path) {
        '/find' => http.Response(
          '[{"path":{"text":"main.dart"},"lines":{"text":"void main()"},'
          '"line_number":2,"absolute_offset":10,"submatches":'
          '[{"match":{"text":"main"},"start":5,"end":9}]}]',
          200,
        ),
        '/find/file' => http.Response('["lib/main.dart"]', 200),
        '/find/symbol' => http.Response(
          '[{"name":"main","kind":12,"location":{"uri":"lib/main.dart",'
          '"range":{"start":{"line":2,"character":5},'
          '"end":{"line":2,"character":9}}}}]',
          200,
        ),
        _ => http.Response('', 404),
      };
    });
    final repository = OpenCodeWorkspaceRepository(
      OpenCodeWorkspaceService(OpenCodeTransport(client)),
      const _PasswordStore(null),
    );

    final text = await repository.search(
      profile,
      '/work/lib',
      WorkspaceSearchKind.text,
      'main',
    );
    final files = await repository.search(
      profile,
      '/work/lib',
      WorkspaceSearchKind.file,
      'main',
    );
    final symbols = await repository.search(
      profile,
      '/work/lib',
      WorkspaceSearchKind.symbol,
      'main',
    );

    expect(text, isA<Ok<List<WorkspaceSearchResult>, WorkspaceFailure>>());
    expect(
      (text as Ok<List<WorkspaceSearchResult>, WorkspaceFailure>).value.single,
      isA<WorkspaceTextSearchResult>(),
    );
    expect(files, isA<Ok<List<WorkspaceSearchResult>, WorkspaceFailure>>());
    expect(symbols, isA<Ok<List<WorkspaceSearchResult>, WorkspaceFailure>>());
  });
}

class _PasswordStore implements CredentialsStore {
  const _PasswordStore(this.password);

  final String? password;

  @override
  Future<void> clearPassword(String profileId) async {}

  @override
  Future<String?> readPassword(String profileId) async => password;

  @override
  Future<void> savePassword(String profileId, String? password) async {}
}
