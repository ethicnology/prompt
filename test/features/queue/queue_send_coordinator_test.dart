import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/local/prompt_database.dart' show PromptDatabase;
import 'package:prompt/data/remote/opencode_event_service.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/chat/data/chat_repository.dart';
import 'package:prompt/features/chat/data/opencode_chat_service.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/queue/data/queue_prompts_dao.dart';
import 'package:prompt/features/queue/data/queue_prompts_repository.dart';
import 'package:prompt/features/queue/data/queue_send_coordinator.dart';
import 'package:prompt/features/queue/domain/queue_failure.dart';
import 'package:prompt/features/queue/domain/queue_send_now_failure.dart';
import 'package:prompt/features/queue/domain/queued_prompt.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';

/// Lets Drift's `watch()` timer-scheduled re-query, and any pending
/// microtask chain inside [QueueSendCoordinator] (stream delivery, mocked
/// HTTP round trips, repository writes), reach a fixed point before the
/// next assertion.
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

/// A scripted OpenCode REST backend for `sendPrompt`, `abortSession`, and
/// `sessionStatus`. Each behavior is independently controllable so a test
/// can simulate acceptance, rejection, and transport failure without a
/// real server.
class _ScriptedChatBackend {
  String sessionStatusType = 'idle';
  int promptAsyncStatusCode = 204;
  int abortStatusCode = 200;
  bool abortReturnValue = true;

  /// Delays every `prompt_async` response until this completes, letting a
  /// test observe the queue mid-send before it settles.
  Completer<void>? promptAsyncGate;

  int promptAsyncCallCount = 0;
  int abortCallCount = 0;
  int sessionStatusCallCount = 0;
  final List<String> promptAsyncOrder = <String>[];

  late final http.Client client = MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/prompt_async')) {
      promptAsyncCallCount++;
      promptAsyncOrder.add(_promptText(request.body));
      final gate = promptAsyncGate;
      if (gate != null) {
        await gate.future;
      }
      return http.Response('', promptAsyncStatusCode);
    }
    if (path.endsWith('/abort')) {
      abortCallCount++;
      return http.Response(jsonEncode(abortReturnValue), abortStatusCode);
    }
    if (path == '/session/status') {
      sessionStatusCallCount++;
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

/// A minimal SSE transport whose byte stream is entirely test-controlled,
/// so a test can emit `session.status`/`session.idle` events at exact
/// points in its own timeline instead of racing a real connection.
class _ScriptedEventClient extends http.BaseClient {
  final StreamController<List<int>> _controller = StreamController<List<int>>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(_controller.stream, 200);
  }

  void emit(String type, Map<String, dynamic> properties, {String? directory}) {
    final json = jsonEncode({
      'directory': ?directory,
      'payload': {'type': type, 'properties': properties},
    });
    _controller.add(utf8.encode('data: $json\n\n'));
  }

  /// Does not await [StreamController.close]: its `done` future only
  /// completes once a listener has drained the close event, but a test
  /// that never activated the coordinator never attaches one.
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
  late QueuePromptsRepository queueRepository;
  late _ScriptedChatBackend backend;
  late ChatRepository chatRepository;
  late _ScriptedEventClient eventClient;
  late OpenCodeEventService eventService;
  late QueueSendCoordinator coordinator;
  var nextId = 0;

  setUp(() {
    database = PromptDatabase.forTesting(NativeDatabase.memory());
    nextId = 0;
    queueRepository = QueuePromptsRepository(
      QueuePromptsDao(database),
      idGenerator: () => 'prompt-${nextId++}',
    );
    backend = _ScriptedChatBackend();
    chatRepository = ChatRepository(
      OpenCodeChatService(OpenCodeTransport(backend.client)),
      const _StaticPasswordStore(),
    );
    eventClient = _ScriptedEventClient();
    eventService = OpenCodeEventService(OpenCodeTransport(eventClient));
    coordinator = QueueSendCoordinator(
      queueRepository: queueRepository,
      chatRepository: chatRepository,
      eventService: eventService,
      credentialsStore: const _StaticPasswordStore(),
    );
  });

  tearDown(() async {
    await coordinator.dispose();
    await eventClient.close();
    await database.close();
  });

  Future<QueuedPrompt> enqueue(String text) async {
    final result = await queueRepository.enqueue(
      profile: profile,
      session: session,
      promptText: text,
    );
    return (result as Ok<QueuedPrompt, QueueFailure>).value;
  }

  Future<List<QueuedPrompt>> currentQueue() {
    return queueRepository.watchQueue(profile: profile, session: session).first;
  }

  group('activate', () {
    test('reconciles a persisted sending prompt to paused/submissionUnknown '
        'before any dispatch', () async {
      final prompt = await enqueue('first');
      await queueRepository.markSending(prompt.id);
      backend.sessionStatusType = 'idle';

      await coordinator.activate(profile: profile, session: session);
      await _settle();

      final queue = await currentQueue();
      expect(queue.single.state, QueuedPromptState.paused);
      expect(queue.single.pauseReason, QueuePauseReason.submissionUnknown);
      expect(backend.promptAsyncCallCount, 0);
    });

    test('dispatches the queue head immediately when the authoritative '
        'status is already idle', () async {
      backend.sessionStatusType = 'idle';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      await enqueue('first');
      await _settle();

      final queue = await currentQueue();
      expect(queue.single.state, QueuedPromptState.acknowledged);
      expect(backend.promptAsyncCallCount, 1);
    });
  });

  group('SSE-gated dispatch', () {
    test(
      'holds the queue while busy and dispatches once session.idle arrives',
      () async {
        backend.sessionStatusType = 'busy';
        await coordinator.activate(profile: profile, session: session);
        await _settle();

        await enqueue('first');
        await _settle();
        var queue = await currentQueue();
        expect(queue.single.state, QueuedPromptState.queued);
        expect(backend.promptAsyncCallCount, 0);

        eventClient.emit('session.idle', {'sessionID': session.id});
        await _settle();

        queue = await currentQueue();
        expect(queue.single.state, QueuedPromptState.acknowledged);
        expect(backend.promptAsyncCallCount, 1);
      },
    );

    test('ignores SSE events for another session or directory', () async {
      backend.sessionStatusType = 'busy';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      await enqueue('first');
      await _settle();

      eventClient.emit('session.idle', {'sessionID': 'unrelated-session'});
      eventClient.emit('session.status', {
        'sessionID': session.id,
        'status': {'type': 'idle'},
      }, directory: '/some/other/workspace');
      await _settle();

      final queue = await currentQueue();
      expect(queue.single.state, QueuedPromptState.queued);
      expect(backend.promptAsyncCallCount, 0);
    });

    test('ignores an unmodeled SSE event type', () async {
      backend.sessionStatusType = 'idle';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      eventClient.emit('session.error', {'sessionID': session.id});
      await _settle();

      await enqueue('first');
      await _settle();

      final queue = await currentQueue();
      expect(queue.single.state, QueuedPromptState.acknowledged);
    });
  });

  group('transport-uncertain failures', () {
    test('a prompt_async failure pauses the prompt as submissionUnknown '
        'without retrying', () async {
      backend.sessionStatusType = 'idle';
      backend.promptAsyncStatusCode = 500;
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      await enqueue('first');
      await _settle();

      final queue = await currentQueue();
      expect(queue.single.state, QueuedPromptState.paused);
      expect(queue.single.pauseReason, QueuePauseReason.submissionUnknown);
      expect(backend.promptAsyncCallCount, 1);

      // No auto retry, even after further idle/queue activity settles.
      eventClient.emit('session.status', {
        'sessionID': session.id,
        'status': {'type': 'idle'},
      });
      await _settle();
      expect(backend.promptAsyncCallCount, 1);
    });

    test('a pending submissionUnknown prompt blocks further automatic '
        'dispatch until resumed', () async {
      backend.sessionStatusType = 'idle';
      final stuck = await enqueue('stuck');
      await queueRepository.markSending(stuck.id);

      await coordinator.activate(profile: profile, session: session);
      await _settle();

      final next = await enqueue('next');
      await _settle();

      var queue = await currentQueue();
      expect(
        queue.firstWhere((p) => p.id == next.id).state,
        QueuedPromptState.queued,
      );
      expect(backend.promptAsyncCallCount, 0);

      await queueRepository.markQueued(stuck.id);
      await _settle();

      queue = await currentQueue();
      expect(
        queue.firstWhere((p) => p.id == stuck.id).state,
        QueuedPromptState.acknowledged,
      );
      expect(
        queue.firstWhere((p) => p.id == next.id).state,
        QueuedPromptState.queued,
      );

      eventClient.emit('session.idle', {'sessionID': session.id});
      await _settle();
      queue = await currentQueue();
      expect(
        queue.firstWhere((p) => p.id == next.id).state,
        QueuedPromptState.acknowledged,
      );
    });
  });

  test('a normal enqueue never triggers an abort', () async {
    backend.sessionStatusType = 'busy';
    await coordinator.activate(profile: profile, session: session);
    await _settle();

    await enqueue('first');
    await _settle();
    await enqueue('second');
    await _settle();

    expect(backend.abortCallCount, 0);

    eventClient.emit('session.idle', {'sessionID': session.id});
    await _settle();

    expect(backend.abortCallCount, 0);
  });

  group('sendNow', () {
    test('fails with noActiveSession when nothing is activated', () async {
      final result = await coordinator.sendNow('missing');

      expect(result, isA<Err<void, QueueSendNowFailure>>());
      expect(
        (result as Err<void, QueueSendNowFailure>).failure,
        QueueSendNowFailure.noActiveSession,
      );
    });

    test('fails with promptNotFound for an unknown id', () async {
      backend.sessionStatusType = 'idle';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      final result = await coordinator.sendNow('missing');

      expect(
        (result as Err<void, QueueSendNowFailure>).failure,
        QueueSendNowFailure.promptNotFound,
      );
      expect(backend.abortCallCount, 0);
    });

    test('fails with promptNotQueued for a prompt that already sent', () async {
      backend.sessionStatusType = 'idle';
      final prompt = await enqueue('first');
      await coordinator.activate(profile: profile, session: session);
      await _settle();
      expect(
        (await currentQueue()).single.state,
        QueuedPromptState.acknowledged,
      );

      final result = await coordinator.sendNow(prompt.id);

      expect(
        (result as Err<void, QueueSendNowFailure>).failure,
        QueueSendNowFailure.promptNotQueued,
      );
      expect(backend.abortCallCount, 0);
    });

    test('explicitly aborts, waits for idle, then dispatches the chosen '
        'prompt ahead of the queue head', () async {
      backend.sessionStatusType = 'busy';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      final first = await enqueue('first prompt');
      final second = await enqueue('second prompt');
      await _settle();

      final sendNowResult = await coordinator.sendNow(second.id);
      await _settle();

      expect(sendNowResult, isA<Ok<void, QueueSendNowFailure>>());
      expect(backend.abortCallCount, 1);
      // Still busy: nothing dispatches until idle is observed.
      expect(backend.promptAsyncCallCount, 0);
      expect(
        (await currentQueue()).firstWhere((p) => p.id == first.id).state,
        QueuedPromptState.queued,
      );

      eventClient.emit('session.idle', {'sessionID': session.id});
      await _settle();

      expect(backend.promptAsyncOrder, isNotEmpty);
      expect(backend.promptAsyncOrder.first, 'second prompt');
      final secondRow = (await currentQueue()).firstWhere(
        (p) => p.id == second.id,
      );
      expect(secondRow.state, QueuedPromptState.acknowledged);
    });

    test(
      'surfaces an abort failure without blocking later normal dispatch',
      () async {
        backend.sessionStatusType = 'busy';
        backend.abortStatusCode = 401;
        await coordinator.activate(profile: profile, session: session);
        await _settle();

        final prompt = await enqueue('first');
        await _settle();

        final result = await coordinator.sendNow(prompt.id);
        await _settle();

        expect(
          (result as Err<void, QueueSendNowFailure>).failure,
          QueueSendNowFailure.abortFailed,
        );
        expect(backend.promptAsyncCallCount, 0);

        eventClient.emit('session.idle', {'sessionID': session.id});
        await _settle();

        expect(
          (await currentQueue()).single.state,
          QueuedPromptState.acknowledged,
        );
      },
    );
  });

  group('deactivate and reactivate', () {
    test('a dispatch left in flight by deactivate is reconciled on the next '
        'activation instead of writing a stale outcome', () async {
      backend.sessionStatusType = 'idle';
      final gate = Completer<void>();
      backend.promptAsyncGate = gate;

      await coordinator.activate(profile: profile, session: session);
      await _settle();

      await enqueue('first');
      await _settle();

      var queue = await currentQueue();
      expect(queue.single.state, QueuedPromptState.sending);

      await coordinator.deactivate();
      gate.complete();
      await _settle();

      // The stale continuation must not write an acknowledgment for a
      // session that is no longer active.
      queue = await currentQueue();
      expect(queue.single.state, QueuedPromptState.sending);

      await coordinator.activate(profile: profile, session: session);
      await _settle();

      queue = await currentQueue();
      expect(queue.single.state, QueuedPromptState.paused);
      expect(queue.single.pauseReason, QueuePauseReason.submissionUnknown);
    });

    test(
      'reactivating a session cancels the previous SSE subscription',
      () async {
        backend.sessionStatusType = 'busy';
        await coordinator.activate(profile: profile, session: session);
        await _settle();
        await enqueue('first');
        await _settle();

        await coordinator.deactivate();
        await _settle();

        // An event delivered after deactivation must not resurrect dispatch.
        eventClient.emit('session.idle', {'sessionID': session.id});
        await _settle();

        expect(backend.promptAsyncCallCount, 0);
        expect((await currentQueue()).single.state, QueuedPromptState.queued);
      },
    );
  });

  test(
    'dispose tears down the active session and rejects reactivation',
    () async {
      backend.sessionStatusType = 'idle';
      await coordinator.activate(profile: profile, session: session);
      await _settle();

      await coordinator.dispose();

      expect(
        () => coordinator.activate(profile: profile, session: session),
        throwsStateError,
      );
    },
  );
}
