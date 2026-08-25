import 'package:flutter/material.dart';

import '../../../core/platform/local_notification_service.dart';
import '../../chat/chat.dart';
import '../../capabilities/capabilities.dart';
import '../../connection/connection.dart';
import '../../diagnostics/diagnostics.dart';
import '../../sessions/sessions.dart';
import '../../settings/settings.dart';
import '../../workspace/workspace.dart';
import '../../terminal/terminal.dart';
import '../../voice/voice.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({
    required this.profile,
    required this.sessionsViewModel,
    required this.conversationViewModel,
    required this.capabilitiesViewModel,
    required this.workspaceViewModel,
    required this.terminalViewModel,
    required this.diagnosticsViewModel,
    required this.voiceViewModel,
    required this.localNotificationService,
    required this.themeViewModel,
    required this.onReconnect,
    required this.onDisconnect,
    super.key,
  });

  final ServerProfile profile;
  final SessionsViewModel sessionsViewModel;
  final ConversationViewModel conversationViewModel;
  final CapabilitiesViewModel capabilitiesViewModel;
  final WorkspaceViewModel workspaceViewModel;
  final TerminalViewModel terminalViewModel;
  final DiagnosticsViewModel diagnosticsViewModel;
  final VoiceViewModel voiceViewModel;
  final LocalNotificationService localNotificationService;
  final ThemeViewModel themeViewModel;
  final Future<bool> Function() onReconnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return SessionsScreen(
      profile: profile,
      viewModel: sessionsViewModel,
      onDisconnect: onDisconnect,
      onOpenSession: (session) => _openConversation(context, session),
      onOpenWorkspace: (projects) => _openWorkspace(context, projects),
      onOpenTerminal: () => _openTerminal(context),
      onOpenDiagnostics: () => _openDiagnostics(context),
      onOpenVoiceSettings: () => _openVoiceSettings(context),
    );
  }

  void _openDiagnostics(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiagnosticsScreen(
          profile: profile,
          viewModel: diagnosticsViewModel,
          localNotificationService: localNotificationService,
          themeViewModel: themeViewModel,
          onReconnect: onReconnect,
          onDisconnect: onDisconnect,
        ),
      ),
    );
  }

  void _openVoiceSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VoiceSettingsScreen(viewModel: voiceViewModel),
      ),
    );
  }

  void _openTerminal(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TerminalScreen(profile: profile, viewModel: terminalViewModel),
      ),
    );
  }

  void _openWorkspace(BuildContext context, List<OpenCodeProject> projects) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkspaceScreen(
          profile: profile,
          projects: projects,
          viewModel: workspaceViewModel,
        ),
      ),
    );
  }

  void _openConversation(BuildContext context, OpenCodeSession session) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(
          profile: profile,
          session: session,
          viewModel: conversationViewModel,
          capabilitiesViewModel: capabilitiesViewModel,
          voiceViewModel: voiceViewModel,
          onOpenFork: (forked) => _replaceConversation(context, forked),
        ),
      ),
    );
  }

  void _replaceConversation(BuildContext context, OpenCodeSession session) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(
          profile: profile,
          session: session,
          viewModel: conversationViewModel,
          capabilitiesViewModel: capabilitiesViewModel,
          voiceViewModel: voiceViewModel,
          onOpenFork: (forked) => _replaceConversation(context, forked),
        ),
      ),
    );
  }
}
