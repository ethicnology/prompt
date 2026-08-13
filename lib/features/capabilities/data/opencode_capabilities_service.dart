import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../data/remote/opencode_transport.dart';
import '../../connection/domain/server_profile.dart';

class OpenCodeCapabilitiesService {
  OpenCodeCapabilitiesService(this._transport);

  final OpenCodeTransport _transport;

  Future<OpenCodeCapabilitiesRecord> fetch(
    ServerProfile profile,
    String? password,
  ) async {
    final responses = await Future.wait([
      _get(profile, password, '/provider'),
      _get(profile, password, '/agent'),
      _get(profile, password, '/command'),
    ]);
    return OpenCodeCapabilitiesRecord(
      providers: _parseProviders(jsonDecode(responses[0].body)),
      agents: _parseAgents(jsonDecode(responses[1].body)),
      commands: _parseCommandsBestEffort(jsonDecode(responses[2].body)),
    );
  }

  Future<http.Response> _get(
    ServerProfile profile,
    String? password,
    String path,
  ) async {
    final response = await _transport.get(profile, password, path);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenCodeHttpFailure(response.statusCode);
    }
    return response;
  }
}

class OpenCodeCapabilitiesRecord {
  const OpenCodeCapabilitiesRecord({
    required this.providers,
    required this.agents,
    required this.commands,
  });

  final List<OpenCodeProviderRecord> providers;
  final List<OpenCodeAgentRecord> agents;
  final List<OpenCodeCommandRecord> commands;
}

class OpenCodeProviderRecord {
  const OpenCodeProviderRecord({
    required this.id,
    required this.isConnected,
    required this.models,
  });

  final String id;
  final bool isConnected;
  final List<OpenCodeModelRecord> models;
}

class OpenCodeModelRecord {
  const OpenCodeModelRecord({required this.id, required this.name});

  final String id;
  final String name;
}

class OpenCodeAgentRecord {
  const OpenCodeAgentRecord({
    required this.name,
    required this.mode,
    required this.isBuiltIn,
    this.description,
  });

  final String name;
  final String? description;
  final String mode;
  final bool isBuiltIn;
}

class OpenCodeCommandRecord {
  const OpenCodeCommandRecord({
    required this.name,
    required this.isSubtask,
    this.description,
    this.agentName,
    this.model,
  });

  final String name;
  final String? description;
  final String? agentName;
  final String? model;
  final bool isSubtask;
}

List<OpenCodeProviderRecord> _parseProviders(Object? value) {
  if (value is! Map<String, dynamic> ||
      value['all'] is! List ||
      value['connected'] is! List) {
    throw const FormatException('Provider response is malformed.');
  }
  final connected = value['connected'];
  if (connected is! List || connected.any((id) => id is! String)) {
    throw const FormatException('Provider response is malformed.');
  }
  final connectedIds = connected.cast<String>().toSet();
  final providers = value['all'] as List;
  return providers
      .map<OpenCodeProviderRecord>(
        (provider) => _parseProvider(provider, connectedIds),
      )
      .toList(growable: false);
}

OpenCodeProviderRecord _parseProvider(Object? value, Set<String> connectedIds) {
  if (value is! Map<String, dynamic> ||
      value['id'] is! String ||
      value['models'] is! Map<String, dynamic>) {
    throw const FormatException('Provider is malformed.');
  }
  final id = value['id'] as String;
  final models = value['models'] as Map<String, dynamic>;
  return OpenCodeProviderRecord(
    id: id,
    isConnected: connectedIds.contains(id),
    models: models.entries
        .map((entry) => _parseModel(entry.key, entry.value))
        .toList(growable: false),
  );
}

OpenCodeModelRecord _parseModel(String id, Object? value) {
  if (value is! Map<String, dynamic> || value['name'] is! String) {
    throw const FormatException('Model is malformed.');
  }
  return OpenCodeModelRecord(id: id, name: value['name'] as String);
}

List<OpenCodeAgentRecord> _parseAgents(Object? value) {
  if (value is! List) {
    throw const FormatException('Agent response must be a list.');
  }
  return value.map<OpenCodeAgentRecord>(_parseAgent).toList(growable: false);
}

OpenCodeAgentRecord _parseAgent(Object? value) {
  if (value is! Map<String, dynamic> ||
      value['name'] is! String ||
      value['mode'] is! String ||
      (value['builtIn'] != null && value['builtIn'] is! bool) ||
      (value['description'] != null && value['description'] is! String)) {
    throw const FormatException('Agent is malformed.');
  }
  return OpenCodeAgentRecord(
    name: value['name'] as String,
    description: value['description'] as String?,
    mode: value['mode'] as String,
    isBuiltIn: value['builtIn'] as bool? ?? false,
  );
}

List<OpenCodeCommandRecord> _parseCommandsBestEffort(Object? value) {
  if (value is! List) {
    return const [];
  }
  final commands = <OpenCodeCommandRecord>[];
  for (final candidate in value) {
    try {
      commands.add(_parseCommand(candidate));
    } on FormatException {
      // Slash commands are optional convenience data. A command introduced by
      // a newer server must not disable model and agent selection.
    }
  }
  return commands;
}

OpenCodeCommandRecord _parseCommand(Object? value) {
  if (value is! Map<String, dynamic> ||
      value['name'] is! String ||
      value['template'] is! String ||
      (value['description'] != null && value['description'] is! String) ||
      (value['agent'] != null && value['agent'] is! String) ||
      (value['model'] != null && value['model'] is! String) ||
      (value['subtask'] != null && value['subtask'] is! bool)) {
    throw const FormatException('Command is malformed.');
  }
  return OpenCodeCommandRecord(
    name: value['name'] as String,
    description: value['description'] as String?,
    agentName: value['agent'] as String?,
    model: value['model'] as String?,
    isSubtask: value['subtask'] as bool? ?? false,
  );
}
