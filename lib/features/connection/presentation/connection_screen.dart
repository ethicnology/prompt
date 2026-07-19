import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/connection_result.dart';
import '../domain/server_profile.dart';
import 'connection_view_model.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({
    required this.viewModel,
    required this.onConnected,
    super.key,
  });

  final ConnectionViewModel viewModel;
  final ValueChanged<ServerProfile> onConnected;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _originController = TextEditingController(
    text: 'http://10.80.0.1:4096',
  );
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _originController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final profile = ServerProfile(
      origin: Uri.parse(_originController.text.trim()),
      username: _usernameController.text.trim().isEmpty
          ? null
          : _usernameController.text.trim(),
    );
    final password = _passwordController.text.isEmpty
        ? null
        : _passwordController.text;
    await widget.viewModel.connect(profile, password);
  }

  String? _validateOrigin(String? input) {
    final origin = Uri.tryParse(input?.trim() ?? '');
    if (origin == null || origin.host.isEmpty) {
      return 'Use a complete private server address.';
    }
    if (origin.scheme == 'https') {
      return null;
    }
    if (origin.scheme != 'http') {
      return 'Use an HTTP or HTTPS address.';
    }
    if (kIsWeb) {
      return 'Web browsers require HTTPS, even through WireGuard.';
    }
    if (!_isPrivateIpv4(origin.host)) {
      return 'HTTP is only permitted for a private WireGuard IPv4 address.';
    }
    return null;
  }

  bool _isPrivateIpv4(String host) {
    final octets = host.split('.').map(int.tryParse).toList();
    if (octets.length != 4 || octets.any((octet) => octet == null)) {
      return false;
    }
    final values = octets.cast<int>();
    if (values.any((octet) => octet < 0 || octet > 255)) {
      return false;
    }
    return values[0] == 10 ||
        (values[0] == 172 && values[1] >= 16 && values[1] <= 31) ||
        (values[0] == 192 && values[1] == 168);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: ValueListenableBuilder<ConnectionUiState>(
                  valueListenable: widget.viewModel,
                  builder: (context, state, _) {
                    if (state case ConnectionReady(:final profile)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        widget.onConnected(profile);
                      });
                    }

                    final checking = state is ConnectionChecking;
                    final failure = state is ConnectionError
                        ? state.failure
                        : null;

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 48,
                          color: theme.colorScheme.primary,
                          semanticLabel: 'Private connection',
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Connect Prompt',
                          style: theme.textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Connect to your OpenCode server through WireGuard.',
                          style: theme.textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        TextFormField(
                          controller: _originController,
                          enabled: !checking,
                          autofocus: true,
                          autocorrect: false,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Private server address',
                            hintText: 'http://10.80.0.1:4096',
                          ),
                          validator: _validateOrigin,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _usernameController,
                          enabled: !checking,
                          autocorrect: false,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Username (optional)',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          enabled: !checking,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          onFieldSubmitted: (_) => _connect(),
                          decoration: const InputDecoration(
                            labelText: 'Password (optional)',
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'HTTP is permitted only on a private WireGuard address. Credentials stay on this device.',
                          style: theme.textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                        if (failure != null) ...[
                          const SizedBox(height: 16),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              failure.message,
                              style: TextStyle(color: theme.colorScheme.error),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: checking ? null : _connect,
                          child: checking
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Test private connection'),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
