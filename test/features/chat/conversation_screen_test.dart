import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/chat/data/chat_repository.dart';
import 'package:prompt/features/chat/data/attachment_picker.dart';
import 'package:prompt/features/chat/data/opencode_chat_service.dart';
import 'package:prompt/features/chat/domain/chat_message.dart';
import 'package:prompt/features/chat/domain/pending_approval.dart';
import 'package:prompt/features/chat/domain/permission_response.dart';
import 'package:prompt/features/chat/domain/prompt_attachment.dart';
import 'package:prompt/features/chat/domain/session_artifacts.dart';
import 'package:prompt/features/chat/presentation/conversation_screen.dart';
import 'package:prompt/features/chat/presentation/conversation_view_model.dart';
import 'package:prompt/features/capabilities/data/capabilities_repository.dart';
import 'package:prompt/features/capabilities/data/opencode_capabilities_service.dart';
import 'package:prompt/features/capabilities/domain/open_code_capabilities.dart';
import 'package:prompt/features/capabilities/domain/open_code_slash_command.dart';
import 'package:prompt/features/capabilities/presentation/capabilities_view_model.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/queue/domain/queued_prompt.dart';
import 'package:prompt/features/queue/domain/prompt_execution_options.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';
import 'package:prompt/features/sessions/domain/session_load_result.dart';
import 'package:prompt/features/sessions/data/opencode_sessions_service.dart';
import 'package:prompt/features/sessions/data/sessions_repository.dart';
import 'package:prompt/features/voice/data/voice_engine.dart';
import 'package:prompt/features/voice/data/voice_model_picker.dart';
import 'package:prompt/features/voice/data/voice_repository.dart';
import 'package:prompt/features/voice/domain/voice_language.dart';
import 'package:prompt/features/voice/presentation/voice_view_model.dart';

class _StaticPasswordStore implements CredentialsStore {
  const _StaticPasswordStore();

  @override
  Future<void> clearPassword(String profileId) async {}

  @override
  Future<String?> readPassword(String profileId) async => null;

  @override
  Future<void> savePassword(String profileId, String? password) async {}
}

class _CancelledAttachmentPicker implements AttachmentPicker {
  @override
  Future<AttachmentPickResult> pick() async => const AttachmentPickCancelled();
}

class _VoiceModelPicker implements VoiceModelPicker {
  @override
  Future<String?> pickModelFromUserAction() async => '/model.bin';
}

class _VoiceEngine implements VoiceEngine {
  _VoiceEngine(this.capture);

  final _VoiceCapture capture;

  @override
  Future<Result<void, VoiceEngineFailure>>
  requestMicrophonePermission() async => const Ok(null);

  @override
  Future<Result<VoiceCapture, VoiceEngineFailure>> startCapture({
    required String modelPath,
    required VoiceLanguage language,
  }) async => Ok(capture);
}

class _VoiceCapture implements VoiceCapture {
  _VoiceCapture(this.transcript);

  final String transcript;
  final partials = StreamController<String>();

  @override
  Stream<String> get partialTranscripts => partials.stream;

  @override
  Future<void> release() async {
    unawaited(partials.close());
  }

  @override
  Future<Result<String, VoiceEngineFailure>> stop() async => Ok(transcript);
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
        sessionsRepository: SessionsRepository(
          OpenCodeSessionsService(
            OpenCodeTransport(MockClient((_) async => http.Response('', 404))),
          ),
          const _StaticPasswordStore(),
        ),
        queueRepositoryProvider: () =>
            throw UnsupportedError('not used by the fake'),
        queueCoordinatorProvider: () =>
            throw UnsupportedError('not used by the fake'),
        attachmentPicker: _CancelledAttachmentPicker(),
      );

  int enqueueCallCount = 0;
  int removeCallCount = 0;
  int sendNowCallCount = 0;
  final List<String> enqueuedTexts = <String>[];
  int enqueueCommandCallCount = 0;
  String? lastCommandName;
  String? lastCommandArguments;
  PromptExecutionOptions? lastCommandOptions;
  String? lastRemovedId;
  String? lastSendNowId;
  bool openCalled = false;
  bool leaveCalled = false;
  int refreshCallCount = 0;

  int respondToPermissionCallCount = 0;
  String? lastPermissionId;
  PermissionResponse? lastPermissionResponse;

  int replyToQuestionCallCount = 0;
  String? lastQuestionRequestId;
  List<List<String>>? lastQuestionAnswers;

  int rejectQuestionCallCount = 0;
  String? lastRejectedRequestId;
  String? lastRevertedMessageId;

  int _nextId = 0;

  @override
  Future<void> open(ServerProfile profile, OpenCodeSession session) async {
    openCalled = true;
  }

  @override
  Future<void> reload() async {}

  @override
  Future<void> refreshFromUserAction() async {
    refreshCallCount++;
  }

  @override
  Future<void> leave() async {
    leaveCalled = true;
  }

  @override
  Future<bool> enqueuePrompt(
    String text, {
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
  }) async {
    enqueueCallCount++;
    enqueuedTexts.add(text);
    queue.value = [
      ...queue.value,
      _prompt('prompt-${_nextId++}', text, QueuedPromptState.queued),
    ];
    return true;
  }

  @override
  Future<bool> enqueueCommand(
    String commandName,
    String arguments, {
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
  }) async {
    enqueueCommandCallCount++;
    lastCommandName = commandName;
    lastCommandArguments = arguments;
    lastCommandOptions = executionOptions;
    return true;
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

  @override
  Future<void> respondToPermission(
    String permissionId,
    PermissionResponse response,
  ) async {
    respondToPermissionCallCount++;
    lastPermissionId = permissionId;
    lastPermissionResponse = response;
    pendingApproval.value = null;
  }

  @override
  Future<void> replyToQuestion(
    String requestId,
    List<List<String>> answers,
  ) async {
    replyToQuestionCallCount++;
    lastQuestionRequestId = requestId;
    lastQuestionAnswers = answers;
    pendingApproval.value = null;
  }

  @override
  Future<void> rejectQuestion(String requestId) async {
    rejectQuestionCallCount++;
    lastRejectedRequestId = requestId;
    pendingApproval.value = null;
  }

  @override
  Future<SessionsFailure?> revert(String messageId) async {
    lastRevertedMessageId = messageId;
    return null;
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

  Future<void> pumpScreen(
    WidgetTester tester, {
    CapabilitiesViewModel? capabilitiesViewModel,
    VoiceViewModel? voiceViewModel,
  }) async {
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
          capabilitiesViewModel: capabilitiesViewModel,
          voiceViewModel: voiceViewModel,
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

  testWidgets(
    'hides an empty queue and shows a multi-line composer by default',
    (tester) async {
      await pumpScreen(tester);

      expect(find.text('Queue: empty'), findsNothing);
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.maxLines, greaterThan(1));
      expect(find.byTooltip('Queue this prompt'), findsOneWidget);
    },
  );

  testWidgets('pulling up from the transcript bottom refreshes the session', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady(
      List.generate(
        24,
        (index) => ChatMessage(
          id: 'message-$index',
          role: ChatMessageRole.assistant,
          text: 'Transcript item $index ' * 8,
          createdAt: DateTime.fromMillisecondsSinceEpoch(index + 1),
        ),
      ),
    );
    await pumpScreen(tester);

    // The transcript opens anchored to the newest message, so a pull up from
    // there drags the standard refresh indicator rather than scrolling.
    expect(find.byType(RefreshIndicator), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -220));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(viewModel.refreshCallCount, 1);
  });

  testWidgets('opens anchored to the newest message without scrolling', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady(
      List.generate(
        24,
        (index) => ChatMessage(
          id: 'message-$index',
          role: ChatMessageRole.assistant,
          text: 'Transcript item $index ' * 8,
          createdAt: DateTime.fromMillisecondsSinceEpoch(index + 1),
        ),
      ),
    );
    await pumpScreen(tester);

    expect(find.textContaining('Transcript item 23'), findsOneWidget);
    expect(find.byTooltip('Scroll to latest message'), findsNothing);
  });

  testWidgets('streams voice transcription into the composer', (tester) async {
    final capture = _VoiceCapture('Bonjour le monde');
    final voiceViewModel = VoiceViewModel(
      VoiceRepository(_VoiceEngine(capture), _VoiceModelPicker()),
    );
    await voiceViewModel.selectModelFromUserAction();
    await pumpScreen(tester, voiceViewModel: voiceViewModel);

    expect(find.byTooltip('Start voice input'), findsOneWidget);
    final inputRect = tester.getRect(find.byType(TextField));
    final voiceRect = tester.getRect(find.byTooltip('Start voice input'));
    final attachmentRect = tester.getRect(find.byTooltip('Add attachment'));
    final sendRect = tester.getRect(find.byTooltip('Queue this prompt'));
    expect(inputRect.right, lessThan(voiceRect.left));
    expect(voiceRect.left, lessThan(attachmentRect.left));
    expect(attachmentRect.left, lessThan(sendRect.left));

    await tester.enterText(find.byType(TextField), 'Existing draft');
    await tester.tap(find.byTooltip('Start voice input'));
    await tester.pump();
    capture.partials.add('Bonjour');
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Existing draft\nBonjour',
    );

    await tester.tap(find.byTooltip('Stop voice input'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Existing draft\nBonjour le monde',
    );
    await voiceViewModel.dispose();
  });

  testWidgets(
    'submitting the composer enqueues the prompt instead of sending it '
    'directly, and clears the field',
    (tester) async {
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField), 'Hello session');
      await tester.pump();
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
    await tester.pump();
    await tester.tap(find.byTooltip('Queue this prompt'));
    await tester.pump();

    expect(viewModel.enqueueCallCount, 0);
    expect(find.text('Queue: empty'), findsNothing);
  });

  testWidgets('shows removable attachment chips and queues their prompt', (
    tester,
  ) async {
    viewModel.attachments.value = [
      PromptAttachment(name: 'notes.txt', bytes: Uint8List.fromList([1])),
    ];
    await pumpScreen(tester);

    expect(find.textContaining('notes.txt'), findsOneWidget);
    expect(find.byTooltip('Remove attachment'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Read this');
    await tester.pump();
    await tester.tap(find.byTooltip('Queue this prompt'));
    await tester.pump();

    expect(viewModel.enqueueCallCount, 1);
  });

  testWidgets('removing an attachment chip releases it from the composer', (
    tester,
  ) async {
    final attachment = PromptAttachment(
      name: 'notes.txt',
      bytes: Uint8List.fromList([1]),
    );
    viewModel.attachments.value = [attachment];
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Remove attachment'));
    await tester.pump();

    expect(viewModel.attachments.value, isEmpty);
    expect(attachment.isReleased, isTrue);
  });

  testWidgets('selects a discovered slash command and queues its arguments '
      'with advertised agent and model defaults', (tester) async {
    final capabilities = CapabilitiesViewModel(
      CapabilitiesRepository(
        OpenCodeCapabilitiesService(
          OpenCodeTransport(MockClient((_) async => http.Response('', 404))),
        ),
        const _StaticPasswordStore(),
      ),
    );
    await pumpScreen(tester, capabilitiesViewModel: capabilities);
    capabilities.value = CapabilitiesReady(
      OpenCodeCapabilities(
        models: const [],
        agents: const [],
        commands: const [
          OpenCodeSlashCommand(
            name: 'review',
            description: 'Review the selected files',
            agentName: 'build',
            model: OpenCodeModelReference(
              providerId: 'anthropic',
              modelId: 'claude-sonnet',
            ),
            isSubtask: false,
          ),
        ],
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Choose slash command'));
    await tester.pumpAndSettle();
    expect(find.text('/review'), findsOneWidget);
    await tester.tap(find.text('/review'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'lib/');
    await tester.tap(find.byTooltip('Queue command'));
    await tester.pump();

    expect(viewModel.enqueueCommandCallCount, 1);
    expect(viewModel.lastCommandName, 'review');
    expect(viewModel.lastCommandArguments, 'lib/');
    expect(viewModel.lastCommandOptions!.agentName, 'build');
    expect(viewModel.lastCommandOptions!.modelProviderId, 'anthropic');
    capabilities.dispose();
  });

  testWidgets(
    'shows a send-now control only for a prompt that is still queued',
    (tester) async {
      await pumpScreen(tester);
      await tester.enterText(find.byType(TextField), 'Queued prompt');
      await tester.pump();
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

  testWidgets('offers merging only for queued prompts below the queue head', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextField), 'First');
    await tester.pump();
    await tester.tap(find.byTooltip('Queue this prompt'));
    await tester.pump();

    expect(find.byTooltip('Merge into the prompt above'), findsNothing);

    final queued = viewModel.queue.value.single;
    viewModel.queue.value = [queued, queued];
    await tester.pump();

    expect(find.byTooltip('Merge into the prompt above'), findsOneWidget);
  });

  testWidgets(
    'send now shows a clearly labeled abort confirmation, and only calls '
    'sendNow once confirmed',
    (tester) async {
      await pumpScreen(tester);
      await tester.enterText(find.byType(TextField), 'First');
      await tester.pump();
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
    await tester.pump();
    await tester.tap(find.byTooltip('Queue this prompt'));
    await tester.pump();
    final promptId = viewModel.queue.value.single.id;

    await tester.tap(find.byTooltip('Remove from queue'));
    await tester.pump();

    expect(viewModel.removeCallCount, 1);
    expect(viewModel.lastRemovedId, promptId);
    expect(find.text('Queue: empty'), findsNothing);
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

  testWidgets('renders a live subagent tool before assistant prose', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'task-1',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: '',
        details: const [
          ChatToolDetail(id: 'tool-1', tool: 'task', status: 'running'),
        ],
      ),
    ]);
    await pumpScreen(tester);

    expect(find.text('Subagent task'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
  });

  testWidgets('revert requires confirmation for its specific message ID', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'message-1',
        role: ChatMessageRole.user,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: 'Hi there',
      ),
    ]);
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Revert to this message'));
    await tester.pumpAndSettle();
    expect(find.text('Revert this message?'), findsOneWidget);
    expect(viewModel.lastRevertedMessageId, isNull);

    await tester.tap(find.text('Revert message'));
    await tester.pumpAndSettle();
    expect(viewModel.lastRevertedMessageId, 'message-1');
  });

  testWidgets('never offers revert on an assistant message', (tester) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'assistant-1',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: 'Here is the answer',
      ),
    ]);
    await pumpScreen(tester);

    expect(find.byTooltip('Revert to this message'), findsNothing);
  });

  testWidgets('renders basic Markdown without interpreting HTML', (
    tester,
  ) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'm1',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text:
            '# Heading\n\nUse **bold** and `code`.\n\n```dart\nmain();\n```\n\n[Prompt](https://example.com) <b>not HTML</b>',
      ),
    ]);

    await pumpScreen(tester);

    expect(find.text('Heading'), findsOneWidget);
    expect(find.text('main();'), findsOneWidget);
    expect(find.textContaining('Prompt', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('<b>not HTML</b>', findRichText: true),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Code block'), findsOneWidget);
  });

  testWidgets(
    'keeps malformed Markdown and unsafe link schemes as plain text',
    (tester) async {
      viewModel.messages.value = ConversationReady([
        ChatMessage(
          id: 'm1',
          role: ChatMessageRole.assistant,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          text: '[unsafe](javascript:alert(1)) and **unfinished',
        ),
      ]);

      await pumpScreen(tester);

      expect(
        find.text('[unsafe](javascript:alert(1)) and **unfinished'),
        findsOneWidget,
      );
    },
  );

  testWidgets('renders selectable session todos and file diffs', (
    tester,
  ) async {
    viewModel.artifacts.value = const SessionArtifactsReady(
      todos: [
        SessionTodo(
          id: 'todo-1',
          content: 'Review diff',
          status: SessionTodoStatus.inProgress,
          priority: SessionTodoPriority.high,
        ),
      ],
      diffs: [
        SessionFileDiff(
          file: 'lib/example.dart',
          patch: '@@ -1 +1 @@\n-old line\n+new line',
          additions: 1,
          deletions: 1,
        ),
      ],
    );
    await pumpScreen(tester);

    await tester.tap(find.text('Session artifacts'));
    await tester.pumpAndSettle();

    expect(find.text('Review diff'), findsOneWidget);
    expect(find.text('lib/example.dart'), findsOneWidget);
    expect(find.byType(SelectableText), findsWidgets);
  });

  testWidgets('moves artifacts into a side panel on wide layouts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpScreen(tester);

    expect(find.byType(VerticalDivider), findsOneWidget);
  });

  testWidgets('hides messages without displayable text', (tester) async {
    viewModel.messages.value = ConversationReady([
      ChatMessage(
        id: 'tool-only',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        text: '   ',
      ),
      ChatMessage(
        id: 'm1',
        role: ChatMessageRole.assistant,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1),
        text: 'Visible response',
      ),
    ]);

    await pumpScreen(tester);

    expect(find.text('No text output.'), findsNothing);
    expect(find.text('Visible response'), findsOneWidget);
  });

  testWidgets('deactivates the view model when the screen is left', (
    tester,
  ) async {
    await pumpScreen(tester);
    expect(viewModel.leaveCalled, isFalse);

    await tester.pumpWidget(const SizedBox());

    expect(viewModel.leaveCalled, isTrue);
  });

  group('approval dock', () {
    testWidgets('shows nothing when there is no pending approval', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Allow once'), findsNothing);
      expect(find.text('Submit answers'), findsNothing);
    });

    testWidgets('renders a pending permission with allow once/always/deny, and '
        'submitting once calls respondToPermission', (tester) async {
      viewModel.pendingApproval.value = const PendingPermissionApproval(
        sessionId: 'session-1',
        permissionId: 'perm-1',
        toolType: 'bash',
        title: 'Run rm -rf /tmp/build',
      );

      await pumpScreen(tester);

      expect(find.textContaining('bash'), findsOneWidget);
      expect(find.text('Run rm -rf /tmp/build'), findsOneWidget);
      expect(find.text('Allow once'), findsOneWidget);
      expect(find.text('Always allow'), findsOneWidget);
      expect(find.text('Deny'), findsOneWidget);

      await tester.tap(find.text('Allow once'));
      await tester.pump();

      expect(viewModel.respondToPermissionCallCount, 1);
      expect(viewModel.lastPermissionId, 'perm-1');
      expect(viewModel.lastPermissionResponse, PermissionResponse.once);
    });

    testWidgets('always allow and deny call respondToPermission with the '
        'matching response', (tester) async {
      viewModel.pendingApproval.value = const PendingPermissionApproval(
        sessionId: 'session-1',
        permissionId: 'perm-1',
        toolType: 'edit',
        title: 'Edit a file',
      );
      await pumpScreen(tester);

      await tester.tap(find.text('Always allow'));
      await tester.pump();
      expect(viewModel.lastPermissionResponse, PermissionResponse.always);

      viewModel.pendingApproval.value = const PendingPermissionApproval(
        sessionId: 'session-1',
        permissionId: 'perm-2',
        toolType: 'edit',
        title: 'Edit another file',
      );
      await tester.pump();

      await tester.tap(find.text('Deny'));
      await tester.pump();
      expect(viewModel.lastPermissionResponse, PermissionResponse.reject);
      expect(viewModel.lastPermissionId, 'perm-2');
    });

    testWidgets(
      'renders a pending question with selectable options, and submitting '
      'calls replyToQuestion with the selected label',
      (tester) async {
        viewModel.pendingApproval.value = PendingQuestionApproval(
          sessionId: 'session-1',
          requestId: 'que-1',
          questions: const [
            QuestionPrompt(
              question: 'Which database should I use?',
              header: 'Database choice',
              options: [
                QuestionOption(label: 'Postgres', description: 'Relational'),
                QuestionOption(label: 'SQLite', description: 'Embedded'),
              ],
            ),
          ],
        );

        await pumpScreen(tester);

        expect(find.text('Which database should I use?'), findsOneWidget);
        expect(find.text('Postgres'), findsOneWidget);
        expect(find.text('SQLite'), findsOneWidget);

        // Submit is disabled until an answer is chosen.
        final submitButtonFinder = find.widgetWithText(
          FilledButton,
          'Submit answers',
        );
        expect(
          tester.widget<FilledButton>(submitButtonFinder).onPressed,
          isNull,
        );

        await tester.tap(find.text('Postgres'));
        await tester.pump();

        expect(
          tester.widget<FilledButton>(submitButtonFinder).onPressed,
          isNotNull,
        );

        await tester.tap(submitButtonFinder);
        await tester.pump();

        expect(viewModel.replyToQuestionCallCount, 1);
        expect(viewModel.lastQuestionRequestId, 'que-1');
        expect(viewModel.lastQuestionAnswers, [
          ['Postgres'],
        ]);
      },
    );

    testWidgets('a typed custom answer also enables submit', (tester) async {
      viewModel.pendingApproval.value = PendingQuestionApproval(
        sessionId: 'session-1',
        requestId: 'que-1',
        questions: const [
          QuestionPrompt(
            question: 'Anything else you want me to know?',
            header: 'Other',
            options: [],
          ),
        ],
      );

      await pumpScreen(tester);

      final submitButtonFinder = find.widgetWithText(
        FilledButton,
        'Submit answers',
      );
      expect(tester.widget<FilledButton>(submitButtonFinder).onPressed, isNull);

      // The dock's custom-answer field renders before the composer's
      // `TextField` in the tree.
      await tester.enterText(find.byType(TextField).first, 'Keep it concise');
      await tester.pump();

      expect(
        tester.widget<FilledButton>(submitButtonFinder).onPressed,
        isNotNull,
      );

      await tester.tap(submitButtonFinder);
      await tester.pump();

      expect(viewModel.lastQuestionAnswers, [
        ['Keep it concise'],
      ]);
    });

    testWidgets('reject calls rejectQuestion with the request id', (
      tester,
    ) async {
      viewModel.pendingApproval.value = PendingQuestionApproval(
        sessionId: 'session-1',
        requestId: 'que-1',
        questions: const [
          QuestionPrompt(
            question: 'Which database should I use?',
            header: 'Database choice',
            options: [
              QuestionOption(label: 'Postgres', description: 'Relational'),
            ],
          ),
        ],
      );

      await pumpScreen(tester);

      await tester.tap(find.text('Reject'));
      await tester.pump();

      expect(viewModel.rejectQuestionCallCount, 1);
      expect(viewModel.lastRejectedRequestId, 'que-1');
    });
  });
}
