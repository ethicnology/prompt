import 'package:flutter/material.dart';

import '../../../core/platform/local_notification_service.dart';
import '../../settings/presentation/notification_settings_screen.dart';
import '../../connection/domain/server_profile.dart';
import '../domain/diagnostics_snapshot.dart';
import 'diagnostics_view_model.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({
    required this.profile,
    required this.viewModel,
    required this.localNotificationService,
    required this.onReconnect,
    required this.onDisconnect,
    super.key,
  });

  final ServerProfile profile;
  final DiagnosticsViewModel viewModel;
  final LocalNotificationService localNotificationService;
  final Future<bool> Function() onReconnect;
  final VoidCallback onDisconnect;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  bool _reconnecting = false;

  @override
  void initState() {
    super.initState();
    widget.viewModel.load(widget.profile);
  }

  Future<void> _reconnect() async {
    setState(() => _reconnecting = true);
    final succeeded = await widget.onReconnect();
    if (!mounted) {
      return;
    }
    setState(() => _reconnecting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          succeeded ? 'Connection restored' : 'Unable to reconnect right now',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Server settings')),
      body: ValueListenableBuilder<DiagnosticsUiState>(
        valueListenable: widget.viewModel,
        builder: (context, state, _) => RefreshIndicator(
          onRefresh: widget.viewModel.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _ConnectionCard(
                profile: widget.profile,
                reconnecting: _reconnecting,
                onReconnect: _reconnecting ? null : _reconnect,
                onDisconnect: widget.onDisconnect,
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Notifications'),
                  subtitle: const Text('Opt in to generic session alerts'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => NotificationSettingsScreen(
                        service: widget.localNotificationService,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              switch (state) {
                DiagnosticsIdle() ||
                DiagnosticsLoading() => const _LoadingDiagnostics(),
                DiagnosticsReady(:final snapshot) => _DiagnosticsSummary(
                  snapshot: snapshot,
                ),
                DiagnosticsError() => _DiagnosticsUnavailable(
                  onRetry: widget.viewModel.refresh,
                ),
              },
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.profile,
    required this.reconnecting,
    required this.onReconnect,
    required this.onDisconnect,
  });

  final ServerProfile profile;
  final bool reconnecting;
  final VoidCallback? onReconnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connection', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(profile.displayOrigin, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onReconnect,
                  icon: reconnecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: const Text('Reconnect'),
                ),
                TextButton.icon(
                  onPressed: onDisconnect,
                  icon: const Icon(Icons.power_settings_new_rounded),
                  label: const Text('Disconnect'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingDiagnostics extends StatelessWidget {
  const _LoadingDiagnostics();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Semantics(
          label: 'Loading server diagnostics',
          child: const CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class _DiagnosticsUnavailable extends StatelessWidget {
  const _DiagnosticsUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Diagnostics unavailable',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'The server did not provide a safe diagnostics summary.',
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticsSummary extends StatelessWidget {
  const _DiagnosticsSummary({required this.snapshot});

  final DiagnosticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 680 ? 2 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: width,
              child: _StatusCard(
                title: 'Server health',
                status: snapshot.isHealthy ? 'Healthy' : 'Needs attention',
                detail: 'Health check completed',
              ),
            ),
            SizedBox(
              width: width,
              child: _StatusCard(
                title: 'MCP servers',
                status: '${snapshot.mcp.total} configured',
                detail:
                    '${snapshot.mcp.connected} connected, '
                    '${snapshot.mcp.needsAttention} need attention, '
                    '${snapshot.mcp.disabled} disabled',
                footer: 'MCP changes are unavailable in this read-only screen.',
              ),
            ),
            SizedBox(
              width: width,
              child: _StatusCard(
                title: 'Language servers',
                status: '${snapshot.lsp.total} reported',
                detail:
                    '${snapshot.lsp.connected} connected, '
                    '${snapshot.lsp.unavailable} unavailable',
              ),
            ),
            SizedBox(
              width: width,
              child: _StatusCard(
                title: 'Formatters',
                status: '${snapshot.formatters.total} reported',
                detail:
                    '${snapshot.formatters.enabled} enabled, '
                    '${snapshot.formatters.disabled} disabled',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.status,
    required this.detail,
    this.footer,
  });

  final String title;
  final String status;
  final String detail;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title: $status. $detail',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(status, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(detail),
              if (footer != null) ...[
                const SizedBox(height: 12),
                Text(footer!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
