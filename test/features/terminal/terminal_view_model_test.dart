import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/terminal/data/terminal_repository.dart';
import 'package:prompt/features/terminal/domain/remote_terminal.dart';
import 'package:prompt/features/terminal/presentation/terminal_view_model.dart';

void main() {
  test('keeps only the newest 100 KiB of streaming terminal output', () async {
    final repository = _Repository();
    final viewModel = TerminalViewModel(
      repository,
      publishInterval: Duration.zero,
    );
    final profile = ServerProfile(origin: Uri.parse('http://10.80.0.1:4096'));
    await viewModel.load(profile, '/work');
    await viewModel.connect(profile, 'pty');
    repository.controller.add(
      List.filled(TerminalViewModel.maxOutputBytes + 20, 65),
    );
    await _settleStream();
    final state = viewModel.value as TerminalReady;
    expect(state.output.codeUnits.length, TerminalViewModel.maxOutputBytes);
    await viewModel.deactivate();
    expect(repository.disconnected, isTrue);
    viewModel.dispose();
  });

  test(
    'renders UTF-8 terminal output without corrupting non-ASCII text',
    () async {
      final repository = _Repository();
      final viewModel = TerminalViewModel(
        repository,
        publishInterval: Duration.zero,
      );
      final profile = ServerProfile(origin: Uri.parse('http://10.80.0.1:4096'));
      await viewModel.load(profile, '/work');
      await viewModel.connect(profile, 'pty');

      repository.controller.add(utf8.encode('cafe \u00e9 \ud83d\ude80'));
      await _settleStream();

      expect(
        (viewModel.value as TerminalReady).output,
        'cafe \u00e9 \ud83d\ude80',
      );
      await viewModel.deactivate();
      viewModel.dispose();
    },
  );

  test('publishes several chunks once and keeps their order', () async {
    final repository = _Repository();
    final viewModel = TerminalViewModel(
      repository,
      publishInterval: Duration.zero,
    );
    final profile = ServerProfile(origin: Uri.parse('http://10.80.0.1:4096'));
    await viewModel.load(profile, '/work');
    await viewModel.connect(profile, 'pty');
    var publications = 0;
    viewModel.addListener(() => publications++);

    repository.controller
      ..add(utf8.encode('one '))
      ..add(utf8.encode('two'));
    await _settleStream();

    expect(publications, 1);
    expect((viewModel.value as TerminalReady).output, 'one two');
    viewModel.dispose();
  });

  test('preserves a UTF-8 sequence split across chunks', () async {
    final repository = _Repository();
    final viewModel = TerminalViewModel(
      repository,
      publishInterval: Duration.zero,
    );
    final profile = ServerProfile(origin: Uri.parse('http://10.80.0.1:4096'));
    await viewModel.load(profile, '/work');
    await viewModel.connect(profile, 'pty');
    repository.controller.add([0xf0, 0x9f]);
    repository.controller.add([0x9a, 0x80]);
    await _settleStream();

    expect((viewModel.value as TerminalReady).output, '🚀');
    viewModel.dispose();
  });

  test(
    'flushes immediately when disconnected and never calls back after dispose',
    () async {
      final repository = _Repository();
      final viewModel = TerminalViewModel(
        repository,
        publishInterval: const Duration(hours: 1),
      );
      final profile = ServerProfile(origin: Uri.parse('http://10.80.0.1:4096'));
      await viewModel.load(profile, '/work');
      await viewModel.connect(profile, 'pty');
      var publications = 0;
      viewModel.addListener(() => publications++);
      repository.controller.add(utf8.encode('pending'));
      await Future<void>.delayed(Duration.zero);
      await viewModel.deactivate();
      expect((viewModel.value as TerminalReady).output, 'pending');
      expect(publications, 1);
      viewModel.dispose();
      repository.controller.add(utf8.encode('late'));
      await Future<void>.delayed(Duration.zero);
      expect(publications, 1);
    },
  );
}

Future<void> _settleStream() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _Repository implements TerminalRepository {
  final controller = StreamController<List<int>>();
  bool disconnected = false;
  @override
  Future<Result<void, RemoteTerminalFailure>> close(
    ServerProfile profile,
    String directory,
    String id,
  ) async => const Ok(null);
  @override
  Future<Result<Stream<List<int>>, RemoteTerminalFailure>> connect(
    ServerProfile profile,
    String directory,
    String id,
  ) async => Ok(controller.stream);
  @override
  Future<Result<RemoteTerminal, RemoteTerminalFailure>> create(
    ServerProfile profile,
    String directory,
  ) async => const Err(RemoteTerminalFailure.unavailable);
  @override
  Future<void> disconnect() async {
    disconnected = true;
  }

  @override
  Future<Result<List<RemoteTerminal>, RemoteTerminalFailure>> list(
    ServerProfile profile,
    String directory,
  ) async => const Ok([
    RemoteTerminal(
      id: 'pty',
      title: 'shell',
      command: 'sh',
      args: [],
      cwd: '/work',
      isRunning: true,
      pid: 1,
    ),
  ]);
  @override
  void send(List<int> bytes) {}
}
