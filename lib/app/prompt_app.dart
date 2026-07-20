import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/security/secure_credentials_service.dart';
import '../data/remote/opencode_transport.dart';
import '../features/chat/data/chat_repository.dart';
import '../features/chat/data/opencode_chat_service.dart';
import '../features/chat/presentation/conversation_view_model.dart';
import '../features/connection/data/connection_repository.dart';
import '../features/connection/data/opencode_health_service.dart';
import '../features/connection/domain/server_profile.dart';
import '../features/connection/presentation/connection_screen.dart';
import '../features/connection/presentation/connection_view_model.dart';
import '../features/home/presentation/home_shell.dart';
import '../features/sessions/data/opencode_sessions_service.dart';
import '../features/sessions/data/sessions_repository.dart';
import '../features/sessions/presentation/sessions_view_model.dart';
import 'prompt_theme.dart';

class PromptApp extends StatefulWidget {
  const PromptApp({super.key});

  @override
  State<PromptApp> createState() => _PromptAppState();
}

class _PromptAppState extends State<PromptApp> {
  late final http.Client _httpClient;
  late final ConnectionViewModel _connectionViewModel;
  late final SessionsViewModel _sessionsViewModel;
  late final ConversationViewModel _conversationViewModel;
  ServerProfile? _connectedProfile;

  @override
  void initState() {
    super.initState();
    _httpClient = http.Client();
    final credentials = SecureCredentialsService(const FlutterSecureStorage());
    final transport = OpenCodeTransport(_httpClient);
    _connectionViewModel = ConnectionViewModel(
      ConnectionRepository(OpenCodeHealthService(transport), credentials),
    );
    _sessionsViewModel = SessionsViewModel(
      SessionsRepository(OpenCodeSessionsService(transport), credentials),
    );
    _conversationViewModel = ConversationViewModel(
      ChatRepository(OpenCodeChatService(transport), credentials),
    );
  }

  @override
  void dispose() {
    _connectionViewModel.dispose();
    _sessionsViewModel.dispose();
    _conversationViewModel.dispose();
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
}
