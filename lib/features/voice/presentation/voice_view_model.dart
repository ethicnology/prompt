import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/async/result.dart';
import '../data/voice_repository.dart';
import '../domain/voice_failure.dart';

sealed class VoiceUiState {
  const VoiceUiState();
}

class VoiceIdle extends VoiceUiState {
  const VoiceIdle();
}

class VoiceStarting extends VoiceUiState {
  const VoiceStarting();
}

class VoiceRecording extends VoiceUiState {
  const VoiceRecording(this.partialTranscript);

  final String partialTranscript;
}

class VoiceTranscribing extends VoiceUiState {
  const VoiceTranscribing();
}

class VoiceTranscriptReady extends VoiceUiState {
  const VoiceTranscriptReady(this.transcript);

  final String transcript;
}

class VoiceUnavailable extends VoiceUiState {
  const VoiceUnavailable(this.failure);

  final VoiceFailure failure;
}

class VoiceViewModel {
  VoiceViewModel(this._repository);

  final VoiceRepository _repository;
  final ValueNotifier<VoiceUiState> state = ValueNotifier(const VoiceIdle());

  /// App-scoped configuration: one selected local model enables voice input
  /// for every conversation until the app is closed or the model is changed.
  final ValueNotifier<bool> hasSelectedModel = ValueNotifier(false);
  StreamSubscription<String>? _partialSubscription;
  bool _disposed = false;

  /// Called only from the visible voice control's user gesture.
  Future<void> selectModelFromUserAction() async {
    if (_disposed) return;
    hasSelectedModel.value = await _repository.selectModelFromUserAction();
  }

  Future<void> startFromUserAction() async {
    if (_disposed) return;
    state.value = const VoiceStarting();
    final result = await _repository.startFromUserAction();
    if (_disposed) {
      await _repository.release();
      return;
    }
    state.value = switch (result) {
      Ok() => _listenForPartials(),
      Err(:final failure) => VoiceUnavailable(failure),
    };
  }

  VoiceUiState _listenForPartials() {
    _partialSubscription?.cancel();
    _partialSubscription = _repository.partialTranscripts.listen(
      (partial) {
        if (!_disposed) state.value = VoiceRecording(partial);
      },
      onError: (_) {
        if (!_disposed) {
          state.value = const VoiceUnavailable(VoiceTranscriptionFailed());
        }
      },
    );
    return const VoiceRecording('');
  }

  Future<void> stopFromUserAction() async {
    if (_disposed) return;
    state.value = const VoiceTranscribing();
    await _partialSubscription?.cancel();
    _partialSubscription = null;
    final result = await _repository.stop();
    if (_disposed) return;
    state.value = switch (result) {
      Ok(:final value) => VoiceTranscriptReady(value),
      Err(:final failure) => VoiceUnavailable(failure),
    };
  }

  Future<void> cancel() async {
    await _partialSubscription?.cancel();
    _partialSubscription = null;
    await _repository.release();
    if (!_disposed) state.value = const VoiceIdle();
  }

  Future<void> notifyAppInactive() => cancel();

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _partialSubscription?.cancel();
    await _repository.release();
    state.dispose();
    hasSelectedModel.dispose();
  }
}
