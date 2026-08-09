import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/async/result.dart';
import '../../connection/domain/server_profile.dart';
import '../data/terminal_repository.dart';
import '../domain/remote_terminal.dart';

sealed class TerminalUiState {
  const TerminalUiState();
}

class TerminalIdle extends TerminalUiState {
  const TerminalIdle();
}

class TerminalLoading extends TerminalUiState {
  const TerminalLoading();
}

class TerminalUnavailable extends TerminalUiState {
  const TerminalUnavailable(this.failure);
  final RemoteTerminalFailure failure;
}

class TerminalReady extends TerminalUiState {
  const TerminalReady({
    required this.directory,
    required this.terminals,
    this.activeId,
    this.output = '',
    this.connecting = false,
    this.failure,
  });
  final String directory;
  final List<RemoteTerminal> terminals;
  final String? activeId;
  final String output;
  final bool connecting;
  final RemoteTerminalFailure? failure;
}

class TerminalViewModel extends ValueNotifier<TerminalUiState> {
  TerminalViewModel(this._repository) : super(const TerminalIdle());
  static const maxOutputBytes = 100 * 1024;
  final TerminalRepository _repository;
  StreamSubscription<List<int>>? _subscription;

  Future<void> load(ServerProfile profile, String directory) async {
    await _disconnect();
    value = const TerminalLoading();
    final result = await _repository.list(profile, directory);
    value = switch (result) {
      Ok<List<RemoteTerminal>, RemoteTerminalFailure>(:final value) =>
        TerminalReady(directory: directory, terminals: value),
      Err<List<RemoteTerminal>, RemoteTerminalFailure>(:final failure) =>
        TerminalUnavailable(failure),
    };
  }

  Future<void> create(ServerProfile profile) async {
    final state = value;
    if (state is! TerminalReady) return;
    final result = await _repository.create(profile, state.directory);
    if (result case Ok<RemoteTerminal, RemoteTerminalFailure>(:final value)) {
      this.value = TerminalReady(
        directory: state.directory,
        terminals: [...state.terminals, value],
      );
    } else if (result case Err<RemoteTerminal, RemoteTerminalFailure>(
      :final failure,
    )) {
      value = TerminalReady(
        directory: state.directory,
        terminals: state.terminals,
        failure: failure,
      );
    }
  }

  Future<void> connect(ServerProfile profile, String id) async {
    final state = value;
    if (state is! TerminalReady) return;
    await _disconnect();
    value = TerminalReady(
      directory: state.directory,
      terminals: state.terminals,
      activeId: id,
      connecting: true,
    );
    final result = await _repository.connect(profile, state.directory, id);
    if (result case Ok<Stream<List<int>>, RemoteTerminalFailure>(
      :final value,
    )) {
      this.value = TerminalReady(
        directory: state.directory,
        terminals: state.terminals,
        activeId: id,
      );
      _subscription = value.listen(
        _append,
        onError: (_, _) => _connectionFailure(),
      );
    } else if (result case Err<Stream<List<int>>, RemoteTerminalFailure>(
      :final failure,
    )) {
      value = TerminalReady(
        directory: state.directory,
        terminals: state.terminals,
        failure: failure,
      );
    }
  }

  Future<void> close(ServerProfile profile, String id) async {
    final state = value;
    if (state is! TerminalReady) return;
    if (state.activeId == id) await _disconnect();
    final result = await _repository.close(profile, state.directory, id);
    if (result case Ok<void, RemoteTerminalFailure>()) {
      value = TerminalReady(
        directory: state.directory,
        terminals: state.terminals
            .where((terminal) => terminal.id != id)
            .toList(growable: false),
      );
    } else if (result case Err<void, RemoteTerminalFailure>(:final failure)) {
      value = TerminalReady(
        directory: state.directory,
        terminals: state.terminals,
        failure: failure,
      );
    }
  }

  void send(String input) {
    if (input.isNotEmpty) {
      _repository.send(utf8.encode(input));
    }
  }

  Future<void> deactivate() => _disconnect();
  void _append(List<int> chunk) {
    final state = value;
    if (state is! TerminalReady) return;
    final combined = utf8.encode(state.output) + chunk;
    final bounded = combined.length <= maxOutputBytes
        ? combined
        : combined.sublist(combined.length - maxOutputBytes);
    final output = utf8.decode(bounded, allowMalformed: true);
    value = TerminalReady(
      directory: state.directory,
      terminals: state.terminals,
      activeId: state.activeId,
      output: output,
    );
  }

  void _connectionFailure() {
    final state = value;
    if (state is TerminalReady) {
      value = TerminalReady(
        directory: state.directory,
        terminals: state.terminals,
        activeId: state.activeId,
        output: state.output,
        failure: RemoteTerminalFailure.connectionFailed,
      );
    }
  }

  Future<void> _disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _repository.disconnect();
  }

  @override
  void dispose() {
    unawaited(_disconnect());
    super.dispose();
  }
}
