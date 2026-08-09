import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/capabilities/data/capabilities_repository.dart';
import 'package:prompt/features/capabilities/data/opencode_capabilities_service.dart';
import 'package:prompt/features/capabilities/domain/capabilities_load_result.dart';
import 'package:prompt/features/capabilities/domain/open_code_agent.dart';
import 'package:prompt/features/capabilities/presentation/capabilities_view_model.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';

void main() {
  final profile = ServerProfile(
    origin: Uri.parse('http://10.80.0.1:4096'),
    username: 'opencode',
  );

  CapabilitiesRepository repositoryFor(http.Client client) {
    return CapabilitiesRepository(
      OpenCodeCapabilitiesService(OpenCodeTransport(client)),
      const _PasswordStore(),
    );
  }

  test(
    'loads typed models, agents, and commands from official endpoints',
    () async {
      final requestedPaths = <String>[];
      final client = MockClient((request) async {
        requestedPaths.add(request.url.path);
        switch (request.url.path) {
          case '/provider':
            return http.Response(
              jsonEncode({
                'all': [
                  {
                    'id': 'anthropic',
                    'models': {
                      'claude-sonnet': {'name': 'Claude Sonnet'},
                    },
                  },
                ],
                'default': {},
                'connected': ['anthropic'],
              }),
              200,
            );
          case '/agent':
            return http.Response(
              jsonEncode([
                {
                  'name': 'build',
                  'description': 'Implement changes',
                  'mode': 'primary',
                  'builtIn': true,
                },
              ]),
              200,
            );
          case '/command':
            return http.Response(
              jsonEncode([
                {
                  'name': 'review',
                  'description': 'Review a change',
                  'template': r'Review $ARGUMENTS',
                  'agent': 'build',
                  'model': 'anthropic/claude-sonnet',
                },
              ]),
              200,
            );
        }
        return http.Response('', 404);
      });

      final result = await repositoryFor(client).load(profile);

      expect(requestedPaths, containsAll(['/provider', '/agent', '/command']));
      final loaded = result as CapabilitiesLoaded;
      expect(loaded.capabilities.models.single.providerId, 'anthropic');
      expect(loaded.capabilities.models.single.id, 'claude-sonnet');
      expect(loaded.capabilities.models.single.isProviderConnected, isTrue);
      expect(loaded.capabilities.agents.single.mode, OpenCodeAgentMode.primary);
      expect(
        loaded.capabilities.commands.single.model?.modelId,
        'claude-sonnet',
      );
    },
  );

  test('maps malformed capability payloads to a user-safe failure', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/provider') {
        return http.Response('{}', 200);
      }
      return http.Response('[]', 200);
    });

    final result = await repositoryFor(client).load(profile);

    expect(result, isA<CapabilitiesLoadFailed>());
    expect(
      (result as CapabilitiesLoadFailed).failure,
      CapabilitiesFailure.unexpectedResponse,
    );
  });

  test('view model exposes empty, ready, and retryable states', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      final empty = calls <= 3;
      switch (request.url.path) {
        case '/provider':
          return http.Response(
            jsonEncode({
              'all': empty
                  ? []
                  : [
                      {
                        'id': 'openai',
                        'models': {
                          'gpt-5': {'name': 'GPT-5'},
                        },
                      },
                    ],
              'default': {},
              'connected': [],
            }),
            200,
          );
        case '/agent':
        case '/command':
          return http.Response('[]', 200);
      }
      return http.Response('', 404);
    });
    final viewModel = CapabilitiesViewModel(repositoryFor(client));

    await viewModel.load(profile);
    expect(viewModel.value, isA<CapabilitiesEmpty>());

    await viewModel.retry();
    expect(viewModel.value, isA<CapabilitiesReady>());
    viewModel.dispose();
  });
}

class _PasswordStore implements CredentialsStore {
  const _PasswordStore();

  @override
  Future<void> clearPassword(String profileId) async {}

  @override
  Future<String?> readPassword(String profileId) async => 'secret';

  @override
  Future<void> savePassword(String profileId, String? password) async {}
}
