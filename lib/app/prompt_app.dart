import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../features/connection/data/connection_repository.dart';
import '../features/connection/data/opencode_health_service.dart';
import '../features/connection/domain/server_profile.dart';
import '../features/connection/presentation/connection_screen.dart';
import '../features/connection/presentation/connection_view_model.dart';
import '../features/home/presentation/home_shell.dart';
import 'prompt_theme.dart';

class PromptApp extends StatefulWidget {
  const PromptApp({super.key});

  @override
  State<PromptApp> createState() => _PromptAppState();
}

class _PromptAppState extends State<PromptApp> {
  late final http.Client _httpClient;
  late final ConnectionViewModel _connectionViewModel;
  ServerProfile? _connectedProfile;

  @override
  void initState() {
    super.initState();
    _httpClient = http.Client();
    _connectionViewModel = ConnectionViewModel(
      ConnectionRepository(OpenCodeHealthService(_httpClient)),
    );
  }

  @override
  void dispose() {
    _connectionViewModel.dispose();
    _httpClient.close();
    super.dispose();
  }

  void _openConnectedServer(ServerProfile profile) {
    setState(() => _connectedProfile = profile);
  }

  void _disconnect() {
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
          : HomeShell(profile: _connectedProfile!, onDisconnect: _disconnect),
    );
  }
}
