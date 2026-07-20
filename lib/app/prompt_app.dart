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

  @override
  void initState() {
    super.initState();
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
    _connectionViewModel.dispose();
    _sessionsViewModel.dispose();
    unawaited(_conversationViewModel.dispose());
    unawaited(_queueCoordinator?.dispose());
    unawaited(_database?.close());
    _httpClient.close();
    super.dispose();
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
