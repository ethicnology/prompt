import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/async/result.dart';
import '../core/platform/local_notification_service.dart';
import '../core/security/credentials_store.dart';
import '../core/security/secure_credentials_service.dart';
import '../data/local/prompt_local_storage.dart';
import '../data/remote/opencode_event_service.dart';
import '../data/remote/opencode_transport.dart';
import '../features/chat/data/chat_repository.dart';
import '../features/chat/data/attachment_picker.dart';
import '../features/chat/data/opencode_chat_service.dart';
import '../features/chat/presentation/conversation_view_model.dart';
import '../features/capabilities/data/capabilities_repository.dart';
import '../features/capabilities/data/opencode_capabilities_service.dart';
import '../features/capabilities/presentation/capabilities_view_model.dart';
import '../features/connection/data/connection_repository.dart';
import '../features/connection/data/opencode_health_service.dart';
import '../features/connection/data/server_profile_store.dart';
import '../features/connection/domain/server_profile.dart';
import '../features/connection/presentation/connection_screen.dart';
import '../features/connection/presentation/connection_view_model.dart';
import '../features/diagnostics/data/diagnostics_repository.dart';
import '../features/diagnostics/data/opencode_diagnostics_service.dart';
import '../features/diagnostics/presentation/diagnostics_view_model.dart';
import '../features/settings/data/theme_preference_store.dart';
import '../features/settings/presentation/theme_view_model.dart';
import '../features/home/presentation/home_shell.dart';
import '../features/queue/data/queue_prompts_repository.dart';
import '../features/queue/data/queue_send_coordinator.dart';
import '../features/sessions/data/opencode_sessions_service.dart';
import '../features/sessions/data/sessions_repository.dart';
import '../features/sessions/presentation/sessions_view_model.dart';
import '../features/terminal/data/opencode_terminal_service.dart';
import '../features/terminal/data/terminal_repository.dart';
import '../features/terminal/presentation/terminal_view_model.dart';
import '../features/workspace/data/opencode_workspace_service.dart';
import '../features/workspace/data/workspace_repository.dart';
import '../features/workspace/presentation/workspace_view_model.dart';
import '../features/voice/voice.dart';
import 'prompt_theme.dart';

class PromptApp extends StatefulWidget {
  const PromptApp({
    this.lastProfileLoader,
    this.themePreferenceStore,
    super.key,
  });

  final Future<ServerProfile?> Function()? lastProfileLoader;
  final ThemePreferenceStore? themePreferenceStore;

  @override
  State<PromptApp> createState() => _PromptAppState();
}

class _PromptAppState extends State<PromptApp> {
  late final http.Client _httpClient;
  late final ConnectionViewModel _connectionViewModel;
  late final SessionsViewModel _sessionsViewModel;
  late final ConversationViewModel _conversationViewModel;
  late final CapabilitiesViewModel _capabilitiesViewModel;
  late final WorkspaceViewModel _workspaceViewModel;
  late final TerminalViewModel _terminalViewModel;
  late final DiagnosticsViewModel _diagnosticsViewModel;
  late final VoiceViewModel _voiceViewModel;
  late final ThemeViewModel _themeViewModel;
  late final LocalNotificationService _localNotificationService;
  ServerProfile? _connectedProfile;

  // Opened lazily on the first conversation, not at app startup: opening
  // the queue's local storage starts a background isolate and a platform
  // file lookup that a user (or a test) who never opens a session should
  // never pay for.
  Future<PromptLocalStorageHandle>? _localStorage;
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
          () async => (await _ensureLocalStorage()).serverProfiles,
        ),
      ),
    );
    final sessionsRepository = SessionsRepository(
      OpenCodeSessionsService(transport),
      credentials,
    );
    _sessionsViewModel = SessionsViewModel(sessionsRepository);
    _conversationViewModel = ConversationViewModel(
      chatRepository: chatRepository,
      sessionsRepository: sessionsRepository,
      queueRepositoryProvider: _ensureQueueRepository,
      queueCoordinatorProvider: () => _ensureQueueCoordinator(
        chatRepository: chatRepository,
        eventService: OpenCodeEventService(transport),
        credentialsStore: credentials,
      ),
      attachmentPicker: FilePickerAttachmentPicker(),
    );
    _capabilitiesViewModel = CapabilitiesViewModel(
      CapabilitiesRepository(
        OpenCodeCapabilitiesService(transport),
        credentials,
      ),
    );
    _workspaceViewModel = WorkspaceViewModel(
      OpenCodeWorkspaceRepository(
        OpenCodeWorkspaceService(transport),
        credentials,
      ),
    );
    _terminalViewModel = TerminalViewModel(
      OpenCodeTerminalRepository(
        OpenCodeTerminalService(transport),
        credentials,
      ),
    );
    _diagnosticsViewModel = DiagnosticsViewModel(
      DiagnosticsRepository(OpenCodeDiagnosticsService(transport), credentials),
    );
    _voiceViewModel = VoiceViewModel(
      VoiceRepository(createVoiceEngine(), const FilePickerVoiceModelPicker()),
    );
    _localNotificationService = LocalNotificationService.platform();
    _themeViewModel = ThemeViewModel(
      widget.themePreferenceStore ?? SharedPreferencesThemePreferenceStore(),
    );
    unawaited(_themeViewModel.load());
  }

  Future<PromptLocalStorageHandle> _ensureLocalStorage() {
    return _localStorage ??= _openLocalStorage();
  }

  Future<PromptLocalStorageHandle> _openLocalStorage() async {
    final result = await openPromptLocalStorage();
    return switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => throw LocalStorageUnavailableException(failure),
    };
  }

  Future<QueuePromptsRepository> _ensureQueueRepository() async {
    final storage = await _ensureLocalStorage();
    return QueuePromptsRepository(storage.queuedPrompts);
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
      // Only raised while the app is not foreground, and only after the user
      // enabled notifications. Carries no session content.
      onGenerationFinished: ({required bool failed}) {
        unawaited(
          failed
              ? _localNotificationService.showSessionFailed()
              : _localNotificationService.showSessionCompleted(),
        );
      },
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
    _capabilitiesViewModel.dispose();
    _workspaceViewModel.dispose();
    _terminalViewModel.dispose();
    _diagnosticsViewModel.dispose();
    unawaited(_voiceViewModel.dispose());
    _themeViewModel.dispose();
    unawaited(_queueCoordinator?.dispose());
    final localStorage = _localStorage;
    if (localStorage != null) {
      unawaited(localStorage.then((storage) => storage.close()));
    }
    _httpClient.close();
    super.dispose();
  }

  /// Only `resumed` counts as foreground; `inactive`, `hidden`, `paused`,
  /// and `detached` all cancel the live SSE connection immediately. This
  /// app never maintains a background connection or an aggressive
  /// reconnect loop (see `ARCHITECTURE.md`'s battery/data rules), so
  /// anything short of fully resumed is treated the same way.
  void _handleAppLifecycleStateChange(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _conversationViewModel.releaseAttachments();
      unawaited(_voiceViewModel.notifyAppInactive());
    }
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

  Future<bool> _reconnect() async {
    final profile = _connectedProfile;
    if (profile == null) {
      return false;
    }
    await _connectionViewModel.restore(profile);
    return _connectionViewModel.value is ConnectionReady;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeViewModel,
      builder: (context, themeMode, _) => MaterialApp(
        title: 'Prompt',
        debugShowCheckedModeBanner: false,
        theme: promptTheme(),
        darkTheme: promptDarkTheme(),
        themeMode: themeMode,
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
                capabilitiesViewModel: _capabilitiesViewModel,
                workspaceViewModel: _workspaceViewModel,
                terminalViewModel: _terminalViewModel,
                diagnosticsViewModel: _diagnosticsViewModel,
                voiceViewModel: _voiceViewModel,
                localNotificationService: _localNotificationService,
                themeViewModel: _themeViewModel,
                onReconnect: _reconnect,
                onDisconnect: _disconnect,
              ),
      ),
    );
  }

  Future<ServerProfile?> _loadLastProfile() async {
    final storage = await _ensureLocalStorage();
    return storage.serverProfiles.loadLast();
  }
}
