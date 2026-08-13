import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/core/platform/local_notification_service.dart';
import 'package:prompt/core/platform/local_notification_types.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/diagnostics/data/diagnostics_repository.dart';
import 'package:prompt/features/diagnostics/data/opencode_diagnostics_service.dart';
import 'package:prompt/features/diagnostics/domain/diagnostics_load_result.dart';
import 'package:prompt/features/diagnostics/presentation/diagnostics_view_model.dart';
import 'package:prompt/features/diagnostics/presentation/diagnostics_screen.dart';

void main() {
  final profile = ServerProfile(
    origin: Uri.parse('http://10.80.0.1:4096'),
    username: 'prompt',
  );

  DiagnosticsRepository repositoryFor(http.Client client) {
    return DiagnosticsRepository(
      OpenCodeDiagnosticsService(OpenCodeTransport(client)),
      const _PasswordStore(),
    );
  }

  test(
    'loads only safe diagnostic aggregates from official GET endpoints',
    () async {
      final paths = <String>[];
      final result = await repositoryFor(
        MockClient((request) async {
          paths.add(request.url.path);
          return switch (request.url.path) {
            '/global/health' => http.Response(
              jsonEncode({'healthy': true, 'version': '1.2.3'}),
              200,
            ),
            '/mcp' => http.Response(
              jsonEncode({
                'safe-name': {'status': 'connected'},
                'other': {'status': 'needs_auth'},
                'disabled': {'status': 'disabled'},
              }),
              200,
            ),
            '/lsp' => http.Response(
              jsonEncode([
                {
                  'id': 'typescript',
                  'name': 'TypeScript',
                  'root': '/private',
                  'status': 'connected',
                },
                {
                  'id': 'dart',
                  'name': 'Dart',
                  'root': '/private',
                  'status': 'error',
                },
              ]),
              200,
            ),
            '/formatter' => http.Response(
              jsonEncode([
                {
                  'name': 'prettier',
                  'extensions': ['.ts'],
                  'enabled': true,
                },
                {
                  'name': 'private',
                  'extensions': ['.secret'],
                  'enabled': false,
                },
              ]),
              200,
            ),
            _ => http.Response('', 404),
          };
        }),
      ).load(profile);

      expect(
        paths,
        containsAll(['/global/health', '/mcp', '/lsp', '/formatter']),
      );
      final snapshot = (result as DiagnosticsLoaded).snapshot;
      expect(snapshot.isHealthy, isTrue);
      expect(snapshot.version, '1.2.3');
      expect(snapshot.mcp.connected, 1);
      expect(snapshot.mcp.needsAttention, 1);
      expect(snapshot.mcp.disabled, 1);
      expect(snapshot.lsp.connected, 1);
      expect(snapshot.lsp.unavailable, 1);
      expect(snapshot.formatters.enabled, 1);
      expect(snapshot.formatters.disabled, 1);
    },
  );

  test('maps malformed responses to a safe failure', () async {
    final result = await repositoryFor(
      MockClient((request) async {
        return request.url.path == '/global/health'
            ? http.Response('{"healthy":true}', 200)
            : http.Response('[]', 200);
      }),
    ).load(profile);

    expect(result, isA<DiagnosticsLoadFailed>());
    expect(
      (result as DiagnosticsLoadFailed).failure,
      DiagnosticsFailure.unexpectedResponse,
    );
  });

  test(
    'view model exposes loading result and refreshes the active profile',
    () async {
      var calls = 0;
      final viewModel = DiagnosticsViewModel(
        repositoryFor(
          MockClient((request) async {
            calls++;
            return switch (request.url.path) {
              '/global/health' => http.Response(
                jsonEncode({'healthy': true, 'version': '1.2.3'}),
                200,
              ),
              '/mcp' => http.Response('{}', 200),
              '/lsp' => http.Response('[]', 200),
              '/formatter' => http.Response('[]', 200),
              _ => http.Response('', 404),
            };
          }),
        ),
      );

      await viewModel.load(profile);
      expect(viewModel.value, isA<DiagnosticsReady>());
      await viewModel.refresh();
      expect(viewModel.value, isA<DiagnosticsReady>());
      expect(calls, 8);
      viewModel.dispose();
    },
  );

  testWidgets('renders aggregates without server labels or paths', (
    tester,
  ) async {
    final viewModel = DiagnosticsViewModel(
      repositoryFor(
        MockClient((request) async {
          return switch (request.url.path) {
            '/global/health' => http.Response(
              jsonEncode({'healthy': true, 'version': 'not-shown'}),
              200,
            ),
            '/mcp' => http.Response(
              jsonEncode({
                'internal-tool': {'status': 'connected'},
              }),
              200,
            ),
            '/lsp' => http.Response(
              jsonEncode([
                {
                  'id': 'dart',
                  'name': 'Internal Dart',
                  'root': '/private/workspace',
                  'status': 'connected',
                },
              ]),
              200,
            ),
            '/formatter' => http.Response(
              jsonEncode([
                {
                  'name': 'private-formatter',
                  'extensions': ['.x'],
                  'enabled': true,
                },
              ]),
              200,
            ),
            _ => http.Response('', 404),
          };
        }),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DiagnosticsScreen(
          profile: profile,
          viewModel: viewModel,
          localNotificationService: LocalNotificationService(
            const _UnavailableNotifications(),
          ),
          onReconnect: () async => true,
          onDisconnect: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 configured'), findsOneWidget);
    expect(find.text('1 reported'), findsNWidgets(2));
    expect(find.text('internal-tool'), findsNothing);
    expect(find.text('Internal Dart'), findsNothing);
    expect(find.text('/private/workspace'), findsNothing);
    expect(find.text('private-formatter'), findsNothing);
    viewModel.dispose();
  });

  testWidgets('refreshes server settings with pull to refresh', (tester) async {
    var calls = 0;
    final viewModel = DiagnosticsViewModel(
      repositoryFor(
        MockClient((request) async {
          calls++;
          return switch (request.url.path) {
            '/global/health' => http.Response(
              jsonEncode({'healthy': true, 'version': '1.2.3'}),
              200,
            ),
            '/mcp' => http.Response('{}', 200),
            '/lsp' || '/formatter' => http.Response('[]', 200),
            _ => http.Response('', 404),
          };
        }),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DiagnosticsScreen(
          profile: profile,
          viewModel: viewModel,
          localNotificationService: LocalNotificationService(
            const _UnavailableNotifications(),
          ),
          onReconnect: () async => true,
          onDisconnect: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RefreshIndicator), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();

    expect(calls, 8);
    viewModel.dispose();
  });
}

class _PasswordStore implements CredentialsStore {
  const _PasswordStore();

  @override
  Future<void> clearPassword(String profileId) async {}

  @override
  Future<String?> readPassword(String profileId) async => 'secret';

  @override
  Future<void> savePassword(String profileId, String? password) async {}
}

class _UnavailableNotifications implements LocalNotificationPlatform {
  const _UnavailableNotifications();

  @override
  Future<LocalNotificationPermission> requestPermission() async =>
      LocalNotificationPermission.unavailable;

  @override
  Future<void> showSessionNotification(SessionNotificationKind kind) async {}
}
