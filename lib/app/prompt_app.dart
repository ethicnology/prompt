import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/security/credentials_store.dart';
import '../core/security/secure_credentials_service.dart';
import '../data/local/prompt_database.dart' hide ServerProfile;
import '../data/remote/opencode_event_service.dart';
import '../data/remote/opencode_transport.dart';
import '../features/chat/data/chat_repository.dart';
import '../features/chat/data/opencode_chat_service.dart';
import '../features/chat/presentation/conversation_view_model.dart';
import '../features/connection/data/connection_repository.dart';
import '../features/connection/data/opencode_health_service.dart';
import '../features/connection/data/server_profile_store.dart';
import '../features/connection/domain/server_profile.dart';
import '../features/connection/presentation/connection_screen.dart';
import '../features/connection/presentation/connection_view_model.dart';
import '../features/home/presentation/home_shell.dart';
import '../features/queue/data/queue_prompts_dao.dart';
import '../features/queue/data/queue_prompts_repository.dart';
import '../features/queue/data/queue_send_coordinator.dart';
import '../features/sessions/data/opencode_sessions_service.dart';
import '../features/sessions/data/sessions_repository.dart';
import '../features/sessions/presentation/sessions_view_model.dart';
import 'prompt_theme.dart';

class PromptApp extends StatefulWidget {
  const PromptApp({this.lastProfileLoader, super.key});

  final Future<ServerProfile?> Function()? lastProfileLoader;

  @override
  State<PromptApp> createState() => _PromptAppState();
}

class _PromptAppState extends State<PromptApp> {
  late final http.Client _httpClient;
  late final ConnectionViewModel _connectionViewModel;
  late final SessionsViewModel _sessionsViewModel;
  late final ConversationViewModel _conversationViewModel;
  ServerProfile? _connectedProfile;

  // Opened lazily on the first conversation, not at app startup: opening
  // the queue's database starts a background isolate and a platform file
  // lookup that a user (or a test) who never opens a session should never
  // pay for.
  PromptDatabase? _database;
  QueueSendCoordinator? _queueCoordinator;

  // The app/session lifecycle owner: forwards `AppLifecycleState` into the
  // queue coordinator so its active SSE connection is cancelled while
  // inactive and reconnects (through the coordinator's own bounded
  // backoff) once foreground, rather than a background connection or
  // aggressive reconnect loop persisting. There is at most one
  // `QueueSendCoordinator` for the app's lifetime, opened lazily above, so
  // this listener only ever needs to forward to `_queueCoordinator`
  // itself rather than tracking a set of active sessions.
  late final AppLifecycleListener _appLifecycleListener;

  @override
  void initState() {
    super.initState();
    _appLifecycleListener = AppLifecycleListener(
      onStateChange: _handleAppLifecycleStateChange,
    );
    _httpClient = http.Client();
    final credentials = SecureCredentialsService(const FlutterSecureStorage());
    final transport = OpenCodeTransport(_httpClient);
    final chatRepository = ChatRepository(
      OpenCodeChatService(transport),
      credentials,
    );
    _connectionViewModel = ConnectionViewModel(
      ConnectionRepository(
        OpenCodeHealthService(transport),
        credentials,
        LazyServerProfileStore(
          () async => DriftServerProfileStore(_ensureDatabase()),
        ),
      ),
    );
    _sessionsViewModel = SessionsViewModel(
      SessionsRepository(OpenCodeSessionsService(transport), credentials),
    );
    _conversationViewModel = ConversationViewModel(
      chatRepository: chatRepository,
      queueRepositoryProvider: _ensureQueueRepository,
      queueCoordinatorProvider: () => _ensureQueueCoordinator(
        chatRepository: chatRepository,
        eventService: OpenCodeEventService(transport),
        credentialsStore: credentials,
      ),
    );
  }

  PromptDatabase _ensureDatabase() => _database ??= PromptDatabase();

  Future<QueuePromptsRepository> _ensureQueueRepository() async {
    final database = _ensureDatabase();
    return QueuePromptsRepository(QueuePromptsDao(database));
  }

  Future<QueueSendCoordinator> _ensureQueueCoordinator({
    required ChatRepository chatRepository,
    required OpenCodeEventService eventService,
    required CredentialsStore credentialsStore,
  }) async {
    final existing = _queueCoordinator;
    if (existing != null) {
      return existing;
    }
    final queueRepository = await _ensureQueueRepository();
    final coordinator = QueueSendCoordinator(
      queueRepository: queueRepository,
      chatRepository: chatRepository,
      eventService: eventService,
      credentialsStore: credentialsStore,
    );
    _queueCoordinator = coordinator;
    return coordinator;
  }

  @override
  void dispose() {
    _appLifecycleListener.dispose();
    _connectionViewModel.dispose();
    _sessionsViewModel.dispose();
    unawaited(_conversationViewModel.dispose());
    unawaited(_queueCoordinator?.dispose());
    unawaited(_database?.close());
    _httpClient.close();
    super.dispose();
  }

  /// Only `resumed` counts as foreground; `inactive`, `hidden`, `paused`,
  /// and `detached` all cancel the live SSE connection immediately. This
  /// app never maintains a background connection or an aggressive
  /// reconnect loop (see `ARCHITECTURE.md`'s battery/data rules), so
  /// anything short of fully resumed is treated the same way.
  void _handleAppLifecycleStateChange(AppLifecycleState state) {
    final coordinator = _queueCoordinator;
    if (coordinator == null) {
      return;
    }
    if (state == AppLifecycleState.resumed) {
      coordinator.notifyAppForeground();
    } else {
      coordinator.notifyAppInactive();
    }
  }

  void _openConnectedServer(ServerProfile profile) {
    setState(() => _connectedProfile = profile);
  }

  void _disconnect() {
    _connectionViewModel.reset();
    setState(() => _connectedProfile = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prompt',
      debugShowCheckedModeBanner: false,
      theme: promptTheme(),
      darkTheme: promptDarkTheme(),
      themeMode: ThemeMode.dark,
      home: _connectedProfile == null
          ? ConnectionScreen(
              viewModel: _connectionViewModel,
              profileLoader: widget.lastProfileLoader ?? _loadLastProfile,
              onConnected: _openConnectedServer,
            )
          : HomeShell(
              profile: _connectedProfile!,
              sessionsViewModel: _sessionsViewModel,
              conversationViewModel: _conversationViewModel,
              onDisconnect: _disconnect,
            ),
    );
  }

  Future<ServerProfile?> _loadLastProfile() {
    return DriftServerProfileStore(_ensureDatabase()).loadLast();
  }
}
