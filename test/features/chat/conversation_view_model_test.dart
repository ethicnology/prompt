import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/local/prompt_database.dart' show PromptDatabase;
import 'package:prompt/data/remote/opencode_event_service.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/chat/data/chat_repository.dart';
import 'package:prompt/features/chat/data/opencode_chat_service.dart';
import 'package:prompt/features/chat/presentation/conversation_view_model.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/queue/data/queue_prompts_dao.dart';
import 'package:prompt/features/queue/data/queue_prompts_repository.dart';
import 'package:prompt/features/queue/data/queue_send_coordinator.dart';
import 'package:prompt/features/queue/domain/queued_prompt.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';

/// Lets Drift's `watch()` timer-scheduled re-query, and any pending
/// microtask chain inside the view model or coordinator, reach a fixed
/// point before the next assertion.
Future<void> _settle({int ticks = 25}) async {
  for (var i = 0; i < ticks; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _StaticPasswordStore implements CredentialsStore {
  const _StaticPasswordStore();

  @override
  Future<void> clearPassword(String profileId) async {}

  @override
  Future<String?> readPassword(String profileId) async => 'secret';

  @override
  Future<void> savePassword(String profileId, String? password) async {}
}

/// A scripted OpenCode REST backend covering the transcript load, and the
/// `prompt_async`/`abort`/`session/status` endpoints the queue coordinator
/// depends on.
class _ScriptedChatBackend {
  String sessionStatusType = 'idle';
  int promptAsyncStatusCode = 204;
  int abortStatusCode = 200;
  bool abortReturnValue = true;

  int promptAsyncCallCount = 0;
  int abortCallCount = 0;
  final List<String> promptAsyncOrder = <String>[];

  late final http.Client client = MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/message')) {
      return http.Response('[]', 200);
    }
    if (path.endsWith('/prompt_async')) {
      promptAsyncCallCount++;
      promptAsyncOrder.add(_promptText(request.body));
      return http.Response('', promptAsyncStatusCode);
    }
    if (path.endsWith('/abort')) {
      abortCallCount++;
      return http.Response(jsonEncode(abortReturnValue), abortStatusCode);
    }
    if (path == '/session/status') {
      return http.Response(
        jsonEncode({
          'session-1': {'type': sessionStatusType},
        }),
        200,
      );
    }
    return http.Response('', 404);
  }

  String _promptText(String body) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final parts = decoded['parts'] as List<dynamic>;
    final first = parts.first as Map<String, dynamic>;
    return first['text'] as String;
  }
}

/// A minimal SSE transport whose byte stream is entirely test-controlled.
class _ScriptedEventClient extends http.BaseClient {
  final StreamController<List<int>> _controller = StreamController<List<int>>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(_controller.stream, 200);
  }

  void emit(String type, Map<String, dynamic> properties) {
    final json = jsonEncode({
      'payload': {'type': type, 'properties': properties},
    });
    _controller.add(utf8.encode('data: $json\n\n'));
  }

  @override
  Future<void> close() {
    unawaited(_controller.close());
    return Future<void>.value();
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

  late PromptDatabase database;
  late _ScriptedChatBackend backend;
  late ChatRepository chatRepository;
  late _ScriptedEventClient eventClient;
  late OpenCodeEventService eventService;
  late int repositoryProviderCallCount;
  late int coordinatorProviderCallCount;
  late ConversationViewModel viewModel;

  QueuePromptsRepository buildQueueRepository() {
    return QueuePromptsRepository(QueuePromptsDao(database));
  }

  setUp(() {
    database = PromptDatabase.forTesting(NativeDatabase.memory());
    backend = _ScriptedChatBackend();
    chatRepository = ChatRepository(
      OpenCodeChatService(OpenCodeTransport(backend.client)),
      const _StaticPasswordStore(),
    );
    eventClient = _ScriptedEventClient();
    eventService = OpenCodeEventService(OpenCodeTransport(eventClient));
    repositoryProviderCallCount = 0;
    coordinatorProviderCallCount = 0;

    QueuePromptsRepository? sharedRepository;
    QueueSendCoordinator? sharedCoordinator;

    viewModel = ConversationViewModel(
      chatRepository: chatRepository,
      queueRepositoryProvider: () async {
        repositoryProviderCallCount++;
        return sharedRepository ??= buildQueueRepository();
      },
      queueCoordinatorProvider: () async {
        coordinatorProviderCallCount++;
        sharedRepository ??= buildQueueRepository();
        return sharedCoordinator ??= QueueSendCoordinator(
          queueRepository: sharedRepository!,
          chatRepository: chatRepository,
          eventService: eventService,
          credentialsStore: const _StaticPasswordStore(),
        );
      },
    );
  });

  tearDown(() async {
    await viewModel.dispose();
    await eventClient.close();
    await database.close();
  });

  test('never opens the queue database before a conversation is opened', () {
    expect(repositoryProviderCallCount, 0);
    expect(coordinatorProviderCallCount, 0);
  });

  test('open loads the transcript and reports an empty queue for a fresh '
      'session', () async {
    backend.sessionStatusType = 'idle';

    await viewModel.open(profile, session);
    await _settle();

    expect(viewModel.messages.value, isA<ConversationReady>());
    expect(viewModel.queue.value, isEmpty);
    expect(repositoryProviderCallCount, 1);
    expect(coordinatorProviderCallCount, 1);
  });

  test('enqueuePrompt durably queues text and the coordinator dispatches it '
      'once idle, never bypassing the queue', () async {
    backend.sessionStatusType = 'idle';
    await viewModel.open(profile, session);
    await _settle();

    await viewModel.enqueuePrompt('hello there');
    await _settle();

    expect(viewModel.queue.value, hasLength(1));
    expect(viewModel.queue.value.single.state, QueuedPromptState.acknowledged);
    expect(backend.promptAsyncCallCount, 1);
    expect(backend.promptAsyncOrder.single, 'hello there');
  });

  test('enqueuePrompt queues while busy instead of sending directly', () async {
    backend.sessionStatusType = 'busy';
    await viewModel.open(profile, session);
    await _settle();

    await viewModel.enqueuePrompt('queued while busy');
    await _settle();

    expect(viewModel.queue.value.single.state, QueuedPromptState.queued);
    expect(backend.promptAsyncCallCount, 0);
    expect(backend.abortCallCount, 0);
  });

  test('removeFromQueue removes a queued prompt', () async {
    backend.sessionStatusType = 'busy';
    await viewModel.open(profile, session);
    await _settle();
    await viewModel.enqueuePrompt('first');
    await _settle();
    final promptId = viewModel.queue.value.single.id;

    await viewModel.removeFromQueue(promptId);
    await _settle();

    expect(viewModel.queue.value, isEmpty);
  });

  test('removeFromQueue reports a rejected removal on queueErrors', () async {
    backend.sessionStatusType = 'idle';
    await viewModel.open(profile, session);
    await _settle();

    final errors = <String>[];
    final subscription = viewModel.queueErrors.listen(errors.add);

    await viewModel.removeFromQueue('does-not-exist');
    await _settle();

    expect(errors, isNotEmpty);
    await subscription.cancel();
  });

  test(
    'sendNow explicitly aborts the active generation before dispatching',
    () async {
      backend.sessionStatusType = 'busy';
      await viewModel.open(profile, session);
      await _settle();

      await viewModel.enqueuePrompt('first');
      await viewModel.enqueuePrompt('second');
      await _settle();
      final second = viewModel.queue.value.last;

      await viewModel.sendNow(second.id);
      await _settle();

      expect(backend.abortCallCount, 1);
      expect(backend.promptAsyncCallCount, 0);

      eventClient.emit('session.idle', {'sessionID': session.id});
      await _settle();

      expect(backend.promptAsyncOrder.first, 'second');
    },
  );

  test('leave deactivates coordination so later SSE events do not '
      'dispatch anything', () async {
    backend.sessionStatusType = 'busy';
    await viewModel.open(profile, session);
    await _settle();
    await viewModel.enqueuePrompt('first');
    await _settle();

    await viewModel.leave();
    await _settle();

    eventClient.emit('session.idle', {'sessionID': session.id});
    await _settle();

    expect(backend.promptAsyncCallCount, 0);
  });

  test('opening a different session tears down coordination for the '
      'previous one', () async {
    final otherSession = OpenCodeSession(
      id: 'session-2',
      projectId: 'project-1',
      directory: '/workspace/project',
      title: 'Another session',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );
    backend.sessionStatusType = 'busy';
    await viewModel.open(profile, session);
    await _settle();
    await viewModel.enqueuePrompt('first');
    await _settle();

    await viewModel.open(profile, otherSession);
    await _settle();

    // The queue notifier now reflects the newly opened (empty) session.
    expect(viewModel.queue.value, isEmpty);

    // An SSE event for the first session no longer triggers a dispatch
    // for it, since that session's coordination was torn down.
    eventClient.emit('session.idle', {'sessionID': session.id});
    await _settle();
    expect(backend.promptAsyncCallCount, 0);
  });
}
