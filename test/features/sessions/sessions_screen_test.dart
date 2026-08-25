import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/sessions/data/opencode_sessions_service.dart';
import 'package:prompt/features/sessions/data/sessions_repository.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';
import 'package:prompt/features/sessions/presentation/sessions_screen.dart';
import 'package:prompt/features/sessions/presentation/sessions_view_model.dart';

void main() {
  testWidgets(
    'creates a session from an editable server path without projects',
    (tester) async {
      http.Request? created;
      final client = MockClient((request) async {
        if (request.url.path == '/session' && request.method == 'POST') {
          created = request;
          return http.Response(_sessionJson, 200);
        }
        if (request.url.path == '/session') return http.Response('[]', 200);
        if (request.url.path == '/project') return http.Response('[]', 200);
        return http.Response('', 404);
      });
      final profile = ServerProfile(
        origin: Uri.parse('http://10.80.0.1:4096'),
        username: 'opencode',
      );
      final viewModel = SessionsViewModel(
        SessionsRepository(
          OpenCodeSessionsService(OpenCodeTransport(client)),
          const _PasswordStore(),
        ),
      );
      OpenCodeSession? opened;

      await tester.pumpWidget(
        MaterialApp(
          home: SessionsScreen(
            profile: profile,
            viewModel: viewModel,
            onOpenSession: (session) => opened = session,
            onOpenWorkspace: (_) {},
            onOpenTerminal: () {},
            onOpenDiagnostics: () {},
            onOpenVoiceSettings: () {},
            onDisconnect: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('New session'));
      await tester.pumpAndSettle();

      expect(find.text('Server project path'), findsOneWidget);
      final pathField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Server project path',
      );
      await tester.enterText(pathField, 'relative/path');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create and open'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(pathField, r'\\server\share\project');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create and open'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.enterText(pathField, '/srv/new-project');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create and open'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Create and open'));
      await tester.pumpAndSettle();

      expect(created!.url.queryParameters['directory'], '/srv/new-project');
      expect(opened?.directory, '/srv/new-project');
      viewModel.dispose();
    },
  );

  testWidgets('auto-completes a server directory and selects the suggestion', (
    tester,
  ) async {
    http.Request? created;
    final client = MockClient((request) async {
      if (request.url.path == '/session' && request.method == 'POST') {
        created = request;
        return http.Response(_sessionJson, 200);
      }
      if (request.url.path == '/session') return http.Response('[]', 200);
      if (request.url.path == '/project') return http.Response('[]', 200);
      if (request.url.path == '/file') {
        expect(request.url.queryParameters['directory'], '/srv');
        expect(request.url.queryParameters['path'], '.');
        return http.Response(
          '[{"type":"directory","absolute":"/srv/new-project"},'
          '{"type":"file","absolute":"/srv/news.txt"}]',
          200,
        );
      }
      return http.Response('', 404);
    });
    final profile = ServerProfile(
      origin: Uri.parse('http://10.80.0.1:4096'),
      username: 'opencode',
    );
    final viewModel = SessionsViewModel(
      SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionsScreen(
          profile: profile,
          viewModel: viewModel,
          onOpenSession: (_) {},
          onOpenWorkspace: (_) {},
          onOpenTerminal: () {},
          onOpenDiagnostics: () {},
          onOpenVoiceSettings: () {},
          onDisconnect: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New session'));
    await tester.pumpAndSettle();

    final pathField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Server project path',
    );
    await tester.enterText(pathField, '/srv/ne');
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pumpAndSettle();

    expect(find.text('/srv/new-project'), findsOneWidget);
    await tester.tap(find.text('/srv/new-project'));
    await tester.pump();
    expect(
      tester.widget<TextField>(pathField).controller!.text,
      '/srv/new-project',
    );
    await tester.tap(find.text('Create and open'));
    await tester.pumpAndSettle();

    expect(created!.url.queryParameters['directory'], '/srv/new-project');
    viewModel.dispose();
  });

  testWidgets('offers known project paths before the server search', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.url.path == '/project') {
        return http.Response(
          '[{"id":"known","worktree":"/srv/known-project"}]',
          200,
        );
      }
      if (request.url.path == '/session') return http.Response('[]', 200);
      return http.Response('[]', 200);
    });
    final profile = ServerProfile(
      origin: Uri.parse('http://10.80.0.1:4096'),
      username: 'opencode',
    );
    final viewModel = SessionsViewModel(
      SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionsScreen(
          profile: profile,
          viewModel: viewModel,
          onOpenSession: (_) {},
          onOpenWorkspace: (_) {},
          onOpenTerminal: () {},
          onOpenDiagnostics: () {},
          onOpenVoiceSettings: () {},
          onDisconnect: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New session'));
    await tester.pumpAndSettle();

    expect(find.text('/srv/known-project'), findsWidgets);
    viewModel.dispose();
  });
}

const _sessionJson =
    '{"id":"new","projectID":"project","directory":"/srv/new-project",'
    '"title":"New","time":{"created":1000,"updated":1000}}';

class _PasswordStore implements CredentialsStore {
  const _PasswordStore();

  @override
  Future<void> clearPassword(String profileId) async {}

  @override
  Future<String?> readPassword(String profileId) async => 'secret';

  @override
  Future<void> savePassword(String profileId, String? password) async {}
}
