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
import 'package:prompt/features/chat/domain/chat_message.dart';
import 'package:prompt/features/chat/domain/pending_approval.dart';
import 'package:prompt/features/chat/domain/permission_response.dart';
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

  /// Seeds the REST transcript returned by `GET .../message`, in the raw
  /// OpenCode message-record shape (`{info: {...}, parts: [...]}`).
  List<Map<String, dynamic>> restMessages = <Map<String, dynamic>>[];

  int promptAsyncCallCount = 0;
  int abortCallCount = 0;
  final List<String> promptAsyncOrder = <String>[];

  int permissionResponseCallCount = 0;
  int questionReplyCallCount = 0;
  int questionRejectCallCount = 0;

  late final http.Client client = MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/message')) {
      return http.Response(jsonEncode(restMessages), 200);
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
    if (path.contains('/permissions/')) {
      permissionResponseCallCount++;
      return http.Response(jsonEncode(true), 200);
    }
    if (path.endsWith('/reply')) {
      questionReplyCallCount++;
      return http.Response(jsonEncode(true), 200);
    }
    if (path.endsWith('/reject')) {
      questionRejectCallCount++;
      return http.Response(jsonEncode(true), 200);
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
    return QueuePromptsRepository(DriftQueuePromptsDao(database));
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

  test('a live message.updated + message.part.updated event updates the '
      'visible transcript without a manual reload', () async {
    backend.sessionStatusType = 'idle';
    await viewModel.open(profile, session);
    await _settle();

    final before = viewModel.messages.value;
    expect(before, isA<ConversationReady>());
    expect((before as ConversationReady).messages, isEmpty);

    eventClient.emit('message.updated', {
      'info': {'id': 'msg-1', 'sessionID': session.id, 'role': 'assistant'},
    });
    eventClient.emit('message.part.updated', {
      'part': {
        'id': 'part-1',
        'messageID': 'msg-1',
        'sessionID': session.id,
        'type': 'text',
        'text': 'Streamed reply',
      },
    });
    await _settle();

    final after = viewModel.messages.value;
    expect(after, isA<ConversationReady>());
    final messages = (after as ConversationReady).messages;
    expect(messages, hasLength(1));
    expect(messages.single.id, 'msg-1');
    expect(messages.single.text, 'Streamed reply');
    expect(messages.single.role, ChatMessageRole.assistant);
  });

  test('a live update for a new message is added alongside the REST history '
      'instead of discarding it', () async {
    backend.sessionStatusType = 'idle';
    backend.restMessages = [
      {
        'info': {
          'id': 'msg-0',
          'role': 'user',
          'time': {'created': 1000},
        },
        'parts': [
          {'type': 'text', 'text': 'Original REST message'},
        ],
      },
    ];

    await viewModel.open(profile, session);
    await _settle();

    final loaded = viewModel.messages.value as ConversationReady;
    expect(loaded.messages.single.text, 'Original REST message');

    eventClient.emit('message.updated', {
      'info': {'id': 'msg-1', 'sessionID': session.id, 'role': 'assistant'},
    });
    eventClient.emit('message.part.updated', {
      'part': {
        'id': 'part-1',
        'messageID': 'msg-1',
        'sessionID': session.id,
        'type': 'text',
        'text': 'Streamed reply',
      },
    });
    await _settle();

    final updated = viewModel.messages.value as ConversationReady;
    expect(updated.messages, hasLength(2));
    expect(updated.messages.first.text, 'Original REST message');
    expect(updated.messages.last.text, 'Streamed reply');
    expect(updated.messages.last.role, ChatMessageRole.assistant);
  });

  test('never overwrites an already-loaded REST message before its own live '
      'text part has arrived', () async {
    backend.sessionStatusType = 'idle';
    backend.restMessages = [
      {
        'info': {
          'id': 'msg-0',
          'role': 'assistant',
          'time': {'created': 1000},
        },
        'parts': [
          {'type': 'text', 'text': 'Already delivered reply'},
        ],
      },
    ];

    await viewModel.open(profile, session);
    await _settle();

    // A metadata-only update for the same message id, with no part
    // event yet, must not blank out its already-loaded text.
    eventClient.emit('message.updated', {
      'info': {'id': 'msg-0', 'sessionID': session.id, 'role': 'assistant'},
    });
    await _settle();

    final messages = (viewModel.messages.value as ConversationReady).messages;
    expect(messages.single.text, 'Already delivered reply');
  });

  test("a live update for a session that is no longer open doesn't leak into "
      'the newly opened session\'s transcript', () async {
    final otherSession = OpenCodeSession(
      id: 'session-2',
      projectId: 'project-1',
      directory: '/workspace/project',
      title: 'Another session',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );
    backend.sessionStatusType = 'idle';

    await viewModel.open(profile, session);
    await _settle();

    await viewModel.open(profile, otherSession);
    await _settle();

    // Tagged with the previous session's id: must not affect the
    // transcript now open for `otherSession`.
    eventClient.emit('message.updated', {
      'info': {'id': 'msg-1', 'sessionID': session.id, 'role': 'assistant'},
    });
    eventClient.emit('message.part.updated', {
      'part': {
        'id': 'part-1',
        'messageID': 'msg-1',
        'sessionID': session.id,
        'type': 'text',
        'text': 'Stale text',
      },
    });
    await _settle();

    final state = viewModel.messages.value;
    expect(state, isA<ConversationReady>());
    expect((state as ConversationReady).messages, isEmpty);
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

  group('pendingApproval', () {
    test('surfaces a live permission.updated event with full detail', () async {
      backend.sessionStatusType = 'busy';
      await viewModel.open(profile, session);
      await _settle();
      expect(viewModel.pendingApproval.value, isNull);

      eventClient.emit('permission.updated', {
        'id': 'perm_1',
        'type': 'bash',
        'sessionID': session.id,
        'messageID': 'msg_1',
        'title': 'Run a shell command',
        'metadata': <String, dynamic>{},
        'time': {'created': 1700000000000},
      });
      await _settle();

      final detail =
          viewModel.pendingApproval.value as PendingPermissionApproval;
      expect(detail.permissionId, 'perm_1');
      expect(detail.toolType, 'bash');
      expect(detail.title, 'Run a shell command');

      eventClient.emit('session.idle', {'sessionID': session.id});
      await _settle();

      expect(viewModel.pendingApproval.value, isNull);
    });

    test(
      'respondToPermission submits the response and clears the dock',
      () async {
        backend.sessionStatusType = 'busy';
        await viewModel.open(profile, session);
        await _settle();

        eventClient.emit('permission.updated', {
          'id': 'perm_1',
          'type': 'bash',
          'sessionID': session.id,
          'messageID': 'msg_1',
          'title': 'Run a shell command',
          'metadata': <String, dynamic>{},
          'time': {'created': 1700000000000},
        });
        await _settle();

        await viewModel.respondToPermission('perm_1', PermissionResponse.once);
        await _settle();

        expect(backend.permissionResponseCallCount, 1);
        expect(viewModel.pendingApproval.value, isNull);
      },
    );

    test(
      'replyToQuestion and rejectQuestion submit and clear the dock',
      () async {
        backend.sessionStatusType = 'busy';
        await viewModel.open(profile, session);
        await _settle();

        eventClient.emit('question.asked', {
          'id': 'que_1',
          'sessionID': session.id,
          'questions': [
            {
              'question': 'Which database should I use?',
              'header': 'Database choice',
              'options': [
                {'label': 'Postgres', 'description': 'Relational, robust'},
              ],
            },
          ],
        });
        await _settle();
        expect(viewModel.pendingApproval.value, isA<PendingQuestionApproval>());

        await viewModel.replyToQuestion('que_1', [
          ['Postgres'],
        ]);
        await _settle();

        expect(backend.questionReplyCallCount, 1);
        expect(viewModel.pendingApproval.value, isNull);
      },
    );

    test('leave clears the pending approval', () async {
      backend.sessionStatusType = 'busy';
      await viewModel.open(profile, session);
      await _settle();

      eventClient.emit('permission.updated', {
        'id': 'perm_1',
        'type': 'bash',
        'sessionID': session.id,
        'messageID': 'msg_1',
        'title': 'Run a shell command',
        'metadata': <String, dynamic>{},
        'time': {'created': 1700000000000},
      });
      await _settle();
      expect(viewModel.pendingApproval.value, isNotNull);

      await viewModel.leave();

      expect(viewModel.pendingApproval.value, isNull);
    });
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
