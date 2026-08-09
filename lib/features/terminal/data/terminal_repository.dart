import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/async/result.dart';
import '../../../core/security/credentials_store.dart';
import '../../../data/remote/opencode_transport.dart';
import '../../connection/domain/server_profile.dart';
import '../domain/remote_terminal.dart';
import 'opencode_terminal_service.dart';

abstract interface class TerminalRepository {
  Future<Result<List<RemoteTerminal>, RemoteTerminalFailure>> list(
    ServerProfile profile,
    String directory,
  );
  Future<Result<RemoteTerminal, RemoteTerminalFailure>> create(
    ServerProfile profile,
    String directory,
  );
  Future<Result<void, RemoteTerminalFailure>> close(
    ServerProfile profile,
    String directory,
    String id,
  );
  Future<Result<Stream<List<int>>, RemoteTerminalFailure>> connect(
    ServerProfile profile,
    String directory,
    String id,
  );
  void send(List<int> bytes);
  Future<void> disconnect();
}

class OpenCodeTerminalRepository implements TerminalRepository {
  OpenCodeTerminalRepository(this._service, this._credentialsStore);

  final OpenCodeTerminalService _service;
  final CredentialsStore _credentialsStore;
  WebSocketChannel? _channel;

  @override
  Future<Result<List<RemoteTerminal>, RemoteTerminalFailure>> list(
    ServerProfile profile,
    String directory,
  ) => _run(
    () async => _service.list(
      profile,
      await _credentialsStore.readPassword(profile.id),
      directory,
    ),
  );

  @override
  Future<Result<RemoteTerminal, RemoteTerminalFailure>> create(
    ServerProfile profile,
    String directory,
  ) => _run(
    () async => _service.create(
      profile,
      await _credentialsStore.readPassword(profile.id),
      directory,
    ),
  );

  @override
  Future<Result<void, RemoteTerminalFailure>> close(
    ServerProfile profile,
    String directory,
    String id,
  ) => _run(
    () async => _service.close(
      profile,
      await _credentialsStore.readPassword(profile.id),
      directory,
      id,
    ),
  );

  @override
  Future<Result<Stream<List<int>>, RemoteTerminalFailure>> connect(
    ServerProfile profile,
    String directory,
    String id,
  ) async {
    await disconnect();
    try {
      final ticket = await _service.connectTicket(
        profile,
        await _credentialsStore.readPassword(profile.id),
        directory,
        id,
      );
      final uri = profile.origin
          .resolve('/pty/$id/connect')
          .replace(
            scheme: profile.origin.scheme == 'https' ? 'wss' : 'ws',
            queryParameters: {'ticket': ticket, 'directory': directory},
          );
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      await channel.ready;
      return Ok(
        channel.stream.map(
          (event) => switch (event) {
            // WebSocket text frames are Unicode strings. Convert them back to
            // UTF-8 bytes so the terminal renderer decodes non-ASCII output
            // exactly as it does binary frames.
            String value => Uint8List.fromList(utf8.encode(value)),
            List<int> value => value,
            _ => throw const FormatException('PTY stream is malformed.'),
          },
        ),
      );
    } on FormatException {
      return const Err(RemoteTerminalFailure.unexpectedResponse);
    } on TimeoutException {
      return const Err(RemoteTerminalFailure.connectionFailed);
    } on WebSocketChannelException {
      return const Err(RemoteTerminalFailure.connectionFailed);
    } on http.ClientException {
      return const Err(RemoteTerminalFailure.connectionFailed);
    } on OpenCodeHttpFailure catch (failure) {
      return Err(_httpFailure(failure.statusCode));
    } on InvalidOpenCodeOrigin {
      return const Err(RemoteTerminalFailure.unavailable);
    }
  }

  @override
  void send(List<int> bytes) => _channel?.sink.add(bytes);

  @override
  Future<void> disconnect() async {
    final channel = _channel;
    _channel = null;
    await channel?.sink.close();
  }

  Future<Result<T, RemoteTerminalFailure>> _run<T>(
    Future<T> Function() action,
  ) async {
    try {
      return Ok(await action());
    } on OpenCodeHttpFailure catch (failure) {
      return Err(_httpFailure(failure.statusCode));
    } on TimeoutException {
      return const Err(RemoteTerminalFailure.unavailable);
    } on InvalidOpenCodeOrigin {
      return const Err(RemoteTerminalFailure.unavailable);
    } on http.ClientException {
      return const Err(RemoteTerminalFailure.unavailable);
    } on FormatException {
      return const Err(RemoteTerminalFailure.unexpectedResponse);
    }
  }

  RemoteTerminalFailure _httpFailure(int statusCode) => switch (statusCode) {
    401 || 403 => RemoteTerminalFailure.unauthorized,
    404 || 405 || 501 => RemoteTerminalFailure.unavailable,
    _ => RemoteTerminalFailure.unexpectedResponse,
  };
}
