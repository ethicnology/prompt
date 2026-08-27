import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/app/app_dependencies.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/features/chat/data/chat_repository.dart';
import 'package:prompt/features/chat/data/opencode_chat_service.dart';
import 'package:prompt/features/chat/data/attachment_picker.dart';
import 'package:prompt/features/chat/domain/prompt_attachment.dart';
import 'package:prompt/features/chat/presentation/conversation_view_model.dart';
import 'package:prompt/features/chat/presentation/conversation_screen.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/home/presentation/home_shell.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';
import 'package:prompt/features/sessions/domain/open_code_project.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/sessions/data/opencode_sessions_service.dart';
import 'package:prompt/features/sessions/data/sessions_repository.dart';
import 'package:prompt/features/sessions/presentation/sessions_screen.dart';
import 'package:prompt/features/sessions/presentation/sessions_view_model.dart';

class _NoopAttachmentPicker implements AttachmentPicker {
  @override
  Future<AttachmentPickResult> pick() async => const AttachmentPickCancelled();
}

class _PasswordStore implements CredentialsStore {
  const _PasswordStore();
  @override
  Future<void> clearPassword(String profileId) async {}
  @override
  Future<String?> readPassword(String profileId) async => null;
  @override
  Future<void> savePassword(String profileId, String? password) async {}
}

class _FakeConversationViewModel extends ConversationViewModel {
  _FakeConversationViewModel()
    : super(
        chatRepository: ChatRepository(
          OpenCodeChatService(
            OpenCodeTransport(MockClient((_) async => http.Response('', 404))),
          ),
          const _PasswordStore(),
        ),
        sessionsRepository: SessionsRepository(
          OpenCodeSessionsService(
            OpenCodeTransport(MockClient((_) async => http.Response('', 404))),
          ),
          const _PasswordStore(),
        ),
        queueRepositoryProvider: () async => throw StateError('unused'),
        queueCoordinatorProvider: () async => throw StateError('unused'),
        attachmentPicker: _NoopAttachmentPicker(),
      );

  @override
  Future<void> open(ServerProfile profile, OpenCodeSession session) async {
    messages.value = const ConversationReady([]);
  }

  @override
  Future<void> leaveSession(OpenCodeSession session) async {}
}

void main() {
  final profile = ServerProfile(
    origin: Uri.parse('http://10.80.0.1:4096'),
    username: 'opencode',
  );

  Future<AppDependencies> dependencies() async {
    final client = MockClient((request) async {
      if (request.url.path == '/project') {
        return http.Response(
          '[{"id":"p","worktree":"/srv/p","name":"p"}]',
          200,
        );
      }
      if (request.url.path == '/session') {
        return http.Response(
          '[{"id":"one","projectID":"p","directory":"/srv/p",'
          '"title":"One","time":{"created":1000,"updated":1000}},'
          '{"id":"two","projectID":"p","directory":"/srv/p",'
          '"title":"Two","time":{"created":1000,"updated":1000}}]',
          200,
        );
      }
      if (request.url.path == '/session/status') {
        return http.Response('{}', 200);
      }
      return http.Response('', 404);
    });
    return AppDependencies.create(
      httpClient: client,
      credentialsStore: const _PasswordStore(),
    );
  }

  testWidgets(
    'wide shell keeps catalog and selects detail without navigation',
    (tester) async {
      final deps = await dependencies();
      final conversation = _FakeConversationViewModel();
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      addTearDown(() async {
        await deps.dispose();
        await conversation.dispose();
        await tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeShell(
              profile: profile,
              sessionsViewModel: deps.sessionsViewModel,
              conversationViewModel: conversation,
              capabilitiesViewModel: deps.capabilitiesViewModel,
              workspaceViewModel: deps.workspaceViewModel,
              terminalViewModel: deps.terminalViewModel,
              diagnosticsViewModel: deps.diagnosticsViewModel,
              voiceViewModel: deps.voiceViewModel,
              localNotificationService: deps.localNotificationService,
              themeViewModel: deps.themeViewModel,
              onReconnect: () async => true,
              onDisconnect: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SessionsScreen), findsOneWidget);
      expect(find.byType(Navigator), findsOneWidget);
      expect(find.byType(ConversationScreen), findsOneWidget);
      expect(
        tester
            .widget<ConversationScreen>(find.byType(ConversationScreen))
            .session
            .id,
        'one',
      );
      expect(find.byType(SessionsScreen), findsOneWidget);
      expect(find.text('Start a conversation'), findsNothing);

      final catalogBefore = tester.getRect(find.byType(SessionsScreen)).width;
      await tester.drag(
        find.byKey(const ValueKey('home-session-catalog-divider')),
        const Offset(80, 0),
      );
      await tester.pump();
      expect(
        tester.getRect(find.byType(SessionsScreen)).width,
        greaterThan(catalogBefore),
      );
      expect(find.byType(ConversationScreen), findsOneWidget);

      final replacement = OpenCodeSession(
        id: 'one',
        projectId: 'p',
        directory: '/srv/p',
        title: 'Renamed one',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      );
      deps.sessionsViewModel.value = SessionsReady(
        [replacement],
        const [OpenCodeProject(id: 'p', directory: '/srv/p')],
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final selectedScreen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      expect(selectedScreen.session, same(replacement));
      expect(find.text('Renamed one'), findsNWidgets(2));

      deps.sessionsViewModel.value = const SessionsReady([], []);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(ConversationScreen), findsNothing);
      expect(find.text('Start a conversation'), findsOneWidget);
      expect(
        find.text('Create a session from the catalog to get started.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'wide selection switches session identity and resize restores push navigation',
    (tester) async {
      final deps = await dependencies();
      final conversation = _FakeConversationViewModel();
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      addTearDown(() async {
        await deps.dispose();
        await conversation.dispose();
        await tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeShell(
              profile: profile,
              sessionsViewModel: deps.sessionsViewModel,
              conversationViewModel: conversation,
              capabilitiesViewModel: deps.capabilitiesViewModel,
              workspaceViewModel: deps.workspaceViewModel,
              terminalViewModel: deps.terminalViewModel,
              diagnosticsViewModel: deps.diagnosticsViewModel,
              voiceViewModel: deps.voiceViewModel,
              localNotificationService: deps.localNotificationService,
              themeViewModel: deps.themeViewModel,
              onReconnect: () async => true,
              onDisconnect: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final firstKey = tester
          .widget<ConversationScreen>(find.byType(ConversationScreen))
          .key;
      await tester.tap(find.text('Two'));
      await tester.pump();
      final secondKey = tester
          .widget<ConversationScreen>(find.byType(ConversationScreen))
          .key;
      expect(secondKey, isNot(equals(firstKey)));
      expect(find.text('Two'), findsNWidgets(2));
      await tester.binding.setSurfaceSize(const Size(700, 700));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Two').first);
      await tester.pump();
      expect(find.byType(Navigator), findsOneWidget);
      expect(find.byType(SessionsScreen), findsOneWidget);
    },
  );
}
