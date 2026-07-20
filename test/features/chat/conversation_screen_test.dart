import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/chat/data/chat_repository.dart';
import 'package:prompt/features/chat/data/opencode_chat_service.dart';
import 'package:prompt/features/chat/domain/chat_message.dart';
import 'package:prompt/features/chat/presentation/conversation_screen.dart';
import 'package:prompt/features/chat/presentation/conversation_view_model.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/queue/domain/queued_prompt.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';

class _StaticPasswordStore implements CredentialsStore {
  const _StaticPasswordStore();

  @override
  Future<void> clearPassword(String profileId) async {}

  @override
  Future<String?> readPassword(String profileId) async => null;

  @override
  Future<void> savePassword(String profileId, String? password) async {}
}

/// A [ConversationViewModel] test double that never touches the real
/// queue database, coordinator, or network: it seeds [messages] and
/// [queue] directly, and records every command the screen issues instead
/// of acting on it. The real queue/coordinator wiring (durable enqueue,
/// dispatch, abort-then-send-now, deactivation) is covered end-to-end by
/// `conversation_view_model_test.dart`; this double exists solely to test
/// the screen's rendering and command wiring in isolation.
class _FakeConversationViewModel extends ConversationViewModel {
  _FakeConversationViewModel()
    : super(
        chatRepository: ChatRepository(
          OpenCodeChatService(
            OpenCodeTransport(MockClient((_) async => http.Response('', 404))),
          ),
          const _StaticPasswordStore(),
        ),
        queueRepositoryProvider: () =>
            throw UnsupportedError('not used by the fake'),
        queueCoordinatorProvider: () =>
            throw UnsupportedError('not used by the fake'),
      );

  int enqueueCallCount = 0;
  int removeCallCount = 0;
  int sendNowCallCount = 0;
  final List<String> enqueuedTexts = <String>[];
  String? lastRemovedId;
  String? lastSendNowId;
  bool openCalled = false;
  bool leaveCalled = false;

  int _nextId = 0;

  @override
  Future<void> open(ServerProfile profile, OpenCodeSession session) async {
    openCalled = true;
  }

  @override
  Future<void> reload() async {}

  @override
  Future<void> leave() async {
    leaveCalled = true;
  }

  @override
  Future<void> enqueuePrompt(String text) async {
    enqueueCallCount++;
    enqueuedTexts.add(text);
    queue.value = [
      ...queue.value,
      _prompt('prompt-${_nextId++}', text, QueuedPromptState.queued),
    ];
  }

  @override
  Future<void> removeFromQueue(String promptId) async {
    removeCallCount++;
    lastRemovedId = promptId;
    queue.value = queue.value
        .where((prompt) => prompt.id != promptId)
        .toList(growable: false);
  }

  @override
  Future<void> sendNow(String promptId) async {
    sendNowCallCount++;
    lastSendNowId = promptId;
  }

  QueuedPrompt _prompt(String id, String text, QueuedPromptState state) {
    final now = DateTime.now();
    return QueuedPrompt(
      id: id,
      serverProfileId: 'profile-1',
      sessionId: 'session-1',
      directory: '/workspace/project',
      position: 0,
      promptText: text,
      state: state,
      attemptCount: 0,
      createdAt: now,
      updatedAt: now,
    );
  }
}

void main() {
  final profile = ServerProfile(
    origin: Uri.parse('http://10.80.0.1:4096'),
    username: 'opencode',
  );
  final session = OpenCodeSession(
    id: 'session-1',
    projectId: 'project-1',
    directory: '/workspace/project',
    title: 'A session',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
  );

  late _FakeConversationViewModel viewModel;

  setUp(() {
    viewModel = _FakeConversationViewModel();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    // Default to a settled, empty transcript unless a test seeds its own:
    // the loading state renders an indeterminate `CircularProgressIndicator`,
    // whose animation never lets `pumpAndSettle` return.
    if (viewModel.messages.value is ConversationLoading) {
      viewModel.messages.value = const ConversationReady(<ChatMessage>[]);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: ConversationScreen(
          profile: profile,
          session: session,
          viewModel: viewModel,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('activates the view model for the given session on open', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(viewModel.openCalled, isTrue);
  });

  testWidgets('shows an empty queue and a multi-line composer by default', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Queue: empty'), findsOneWidget);
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.maxLines, greaterThan(1));
    expect(find.byTooltip('Queue this prompt'), findsOneWidget);
  });

  testWidgets(
    'submitting the composer enqueues the prompt instead of sending it '
    'directly, and clears the field',
    (tester) async {
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'Hello session');
      await tester.tap(find.byTooltip('Queue this prompt'));
      await tester.pump();

      expect(viewModel.enqueueCallCount, 1);
      expect(viewModel.enqueuedTexts.single, 'Hello session');
      expect(find.text('Queue: 1 prompt'), findsOneWidget);
      expect(find.text('Hello session'), findsOneWidget);
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, isEmpty);
    },
  );

  testWidgets('never enqueues blank composer text', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byTooltip('Queue this prompt'));
    await tester.pump();

    expect(viewModel.enqueueCallCount, 0);
    expect(find.text('Queue: empty'), findsOneWidget);
  });

  testWidgets(
    'shows a send-now control only for a prompt that is still queued',
    (tester) async {
      await pumpScreen(tester);
      await tester.enterText(find.byType(TextField), 'Queued prompt');
      await tester.tap(find.byTooltip('Queue this prompt'));
      await tester.pump();

      expect(
        find.byTooltip('Send now (aborts current generation)'),
        findsOneWidget,
      );

      // Simulate the coordinator advancing the prompt past `queued`.
      viewModel.queue.value = [
        viewModel.queue.value.single.copyWith(
          state: QueuedPromptState.acknowledged,
        ),
      ];
      await tester.pump();

      expect(
        find.byTooltip('Send now (aborts current generation)'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'send now shows a clearly labeled abort confirmation, and only calls '
    'sendNow once confirmed',
    (tester) async {
      await pumpScreen(tester);
      await tester.enterText(find.byType(TextField), 'First');
      await tester.tap(find.byTooltip('Queue this prompt'));
      await tester.pump();
      final promptId = viewModel.queue.value.single.id;

      await tester.tap(find.byTooltip('Send now (aborts current generation)'));
      await tester.pumpAndSettle();

      expect(
        find.text('Abort current generation and send now?'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'cancels whatever the session is currently '
          'generating',
        ),
        findsOneWidget,
      );
      expect(viewModel.sendNowCallCount, 0);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(viewModel.sendNowCallCount, 0);

      await tester.tap(find.byTooltip('Send now (aborts current generation)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abort & send now'));
      await tester.pumpAndSettle();

      expect(viewModel.sendNowCallCount, 1);
      expect(viewModel.lastSendNowId, promptId);
    },
  );

  testWidgets('remove takes a prompt out of the queue', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextField), 'Removable');
    await tester.tap(find.byTooltip('Queue this prompt'));
    await tester.pump();
    final promptId = viewModel.queue.value.single.id;

    await tester.tap(find.byTooltip('Remove from queue'));
    await tester.pump();

    expect(viewModel.removeCallCount, 1);
    expect(viewModel.lastRemovedId, promptId);
    expect(find.text('Queue: empty'), findsOneWidget);
  });

  testWidgets('renders the loaded transcript', (tester) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'm1',
        role: ChatMessageRole.user,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: 'Hi there',
      ),
    ]);

    await pumpScreen(tester);

    expect(find.text('Hi there'), findsOneWidget);
  });

  testWidgets('deactivates the view model when the screen is left', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(viewModel.leaveCalled, isFalse);

    await tester.pumpWidget(const SizedBox());

    expect(viewModel.leaveCalled, isTrue);
  });
}
