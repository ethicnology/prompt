import 'package:flutter/material.dart';

import '../../connection/connection.dart';
import '../../chat/chat.dart';
import '../../sessions/sessions.dart';
import '../../sessions/presentation/sessions_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    required this.profile,
    required this.sessionsViewModel,
    required this.conversationViewModel,
    required this.onDisconnect,
    super.key,
  });

  final ServerProfile profile;
  final SessionsViewModel sessionsViewModel;
  final ConversationViewModel conversationViewModel;
  final VoidCallback onDisconnect;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.forum_outlined),
      selectedIcon: Icon(Icons.forum),
      label: 'Sessions',
    ),
    NavigationDestination(
      icon: Icon(Icons.difference_outlined),
      selectedIcon: Icon(Icons.difference),
      label: 'Changes',
    ),
    NavigationDestination(
      icon: Icon(Icons.tune_outlined),
      selectedIcon: Icon(Icons.tune),
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wideLayout = MediaQuery.sizeOf(context).width >= 840;
    final labels = ['Sessions', 'Changes', 'Settings'];

    final content = _selectedIndex == 0
        ? _ShellPage(
            title: labels[_selectedIndex],
            onDisconnect: widget.onDisconnect,
            child: SessionsScreen(
              profile: widget.profile,
              viewModel: widget.sessionsViewModel,
              onOpenSession: (session) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ConversationScreen(
                      profile: widget.profile,
                      session: session,
                      viewModel: widget.conversationViewModel,
                    ),
                  ),
                );
              },
            ),
          )
        : _ConnectedEmptyState(
            title: labels[_selectedIndex],
            profile: widget.profile,
            onDisconnect: widget.onDisconnect,
          );

    if (wideLayout) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (index) {
                  setState(() => _selectedIndex = index);
                },
                labelType: NavigationRailLabelType.all,
                destinations: _destinations
                    .map(
                      (destination) => NavigationRailDestination(
                        icon: destination.icon,
                        selectedIcon: destination.selectedIcon,
                        label: Text(destination.label),
                      ),
                    )
                    .toList(),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: content),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(child: content),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        destinations: _destinations,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
      ),
    );
  }
}

class _ConnectedEmptyState extends StatelessWidget {
  const _ConnectedEmptyState({
    required this.title,
    required this.profile,
    required this.onDisconnect,
  });

  final String title;
  final ServerProfile profile;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: onDisconnect,
            icon: const Icon(Icons.link_off),
            tooltip: 'Disconnect',
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Private server connected',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  profile.displayOrigin,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Session synchronization is the next implementation slice.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellPage extends StatelessWidget {
  const _ShellPage({
    required this.title,
    required this.onDisconnect,
    required this.child,
  });

  final String title;
  final VoidCallback onDisconnect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: onDisconnect,
            icon: const Icon(Icons.link_off),
            tooltip: 'Disconnect',
          ),
        ],
      ),
      body: child,
    );
  }
}
