import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/async/result.dart';
import '../../connection/connection.dart';
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
  TerminalViewModel(
    this._repository, {
    this.publishInterval = const Duration(milliseconds: 16),
    Timer Function(Duration, void Function())? timerFactory,
  }) : _timerFactory = timerFactory ?? Timer.new,
       super(const TerminalIdle());
  static const maxOutputBytes = 100 * 1024;
  final TerminalRepository _repository;
  final Duration publishInterval;
  final Timer Function(Duration, void Function()) _timerFactory;
  final _TerminalOutputBuffer _outputBuffer = _TerminalOutputBuffer(
    maxOutputBytes,
  );
  StreamSubscription<List<int>>? _subscription;
  Timer? _publishTimer;
  bool _publishPending = false;
  bool _disposed = false;

  Future<void> load(ServerProfile profile, String directory) async {
    await _disconnect();
    if (_disposed) return;
    _outputBuffer.clear();
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
    if (_disposed) return;
    _outputBuffer.clear();
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
        onDone: _flush,
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
    if (_disposed || value is! TerminalReady) return;
    _outputBuffer.append(chunk);
    _publishPending = true;
    _publishTimer ??= _timerFactory(publishInterval, _flush);
  }

  void _connectionFailure() {
    _flush(RemoteTerminalFailure.connectionFailed);
  }

  void _flush([RemoteTerminalFailure? failure]) {
    _publishTimer?.cancel();
    _publishTimer = null;
    final state = value;
    if (!_disposed &&
        state is TerminalReady &&
        (_publishPending || failure != null)) {
      _publishPending = false;
      value = TerminalReady(
        directory: state.directory,
        terminals: state.terminals,
        activeId: state.activeId,
        output: _outputBuffer.decode(),
        failure: failure ?? state.failure,
      );
    }
  }

  Future<void> _disconnect() async {
    _flush();
    await _subscription?.cancel();
    _subscription = null;
    await _repository.disconnect();
  }

  @override
  void dispose() {
    _flush();
    _disposed = true;
    _publishTimer?.cancel();
    _publishTimer = null;
    _publishPending = false;
    unawaited(_disconnect());
    super.dispose();
  }
}

class _TerminalOutputBuffer {
  _TerminalOutputBuffer(this.maxBytes);

  final int maxBytes;
  final List<int> _bytes = <int>[];
  List<int> _pending = const <int>[];

  void clear() {
    _bytes.clear();
    _pending = const <int>[];
  }

  void append(List<int> chunk) {
    if (chunk.isEmpty) return;
    final input = <int>[..._pending, ...chunk];
    final incomplete = _incompleteSuffixLength(input);
    final completeLength = input.length - incomplete;
    if (completeLength > 0) _bytes.addAll(input.getRange(0, completeLength));
    _pending = incomplete == 0 ? const <int>[] : input.sublist(completeLength);
    if (_bytes.length > maxBytes) {
      _bytes.removeRange(0, _bytes.length - maxBytes);
    }
  }

  String decode() => utf8.decode(_bytes, allowMalformed: true);

  int _incompleteSuffixLength(List<int> input) {
    var continuationCount = 0;
    for (
      var index = input.length - 1;
      index >= 0 && continuationCount < 3 && _isContinuation(input[index]);
      index--
    ) {
      continuationCount++;
    }
    if (continuationCount == 0 || continuationCount == input.length) return 0;
    final lead = input[input.length - continuationCount - 1];
    final expected = lead <= 0x7f
        ? 1
        : lead >= 0xc2 && lead <= 0xdf
        ? 2
        : lead >= 0xe0 && lead <= 0xef
        ? 3
        : lead >= 0xf0 && lead <= 0xf4
        ? 4
        : 0;
    return expected > continuationCount + 1 ? continuationCount + 1 : 0;
  }

  bool _isContinuation(int byte) => byte & 0xc0 == 0x80;
}
