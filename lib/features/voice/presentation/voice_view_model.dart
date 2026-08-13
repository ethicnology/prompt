import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/async/result.dart';
import '../data/voice_repository.dart';
import '../domain/voice_failure.dart';
import '../domain/voice_language.dart';

sealed class VoiceUiState {
  const VoiceUiState();
}

class VoiceIdle extends VoiceUiState {
  const VoiceIdle();
}

class VoiceStarting extends VoiceUiState {
  const VoiceStarting();
}

class VoiceReady extends VoiceUiState {
  const VoiceReady({this.transcript = ''});

  final String transcript;
}

class VoiceRecording extends VoiceUiState {
  const VoiceRecording(this.partialTranscript);

  final String partialTranscript;
}

class VoiceTranscribing extends VoiceUiState {
  const VoiceTranscribing(this.partialTranscript);

  final String partialTranscript;
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
  final ValueNotifier<VoiceLanguage> language = ValueNotifier(
    VoiceLanguage.french,
  );
  StreamSubscription<String>? _partialSubscription;
  bool _disposed = false;
  bool _stopping = false;
  bool _releaseRequested = false;
  bool _modeActive = false;

  /// Called only from the visible voice control's user gesture.
  Future<void> selectModelFromUserAction() async {
    if (_disposed) return;
    hasSelectedModel.value = await _repository.selectModelFromUserAction();
  }

  Future<void> enterModeFromUserAction() async {
    if (_disposed) return;
    _modeActive = true;
    state.value = const VoiceStarting();
    final result = await _repository.prepareFromUserAction();
    if (_disposed || !_modeActive) {
      await _repository.release(releaseModel: true);
      return;
    }
    state.value = switch (result) {
      Ok() => const VoiceReady(),
      Err(:final failure) => () {
        _modeActive = false;
        return VoiceUnavailable(failure);
      }(),
    };
  }

  Future<void> startSegmentFromUserAction() async {
    if (_disposed || !_modeActive || state.value is! VoiceReady) return;
    _releaseRequested = false;
    state.value = const VoiceStarting();
    final result = await _repository.startSegment(language.value);
    if (_disposed || !_modeActive) {
      await _repository.release(releaseModel: true);
      return;
    }
    switch (result) {
      case Ok():
        state.value = _listenForPartials();
        if (_releaseRequested) {
          await finishSegmentFromUserAction();
        }
      case Err(:final failure):
        _modeActive = false;
        state.value = VoiceUnavailable(failure);
    }
  }

  VoiceUiState _listenForPartials() {
    _partialSubscription?.cancel();
    _partialSubscription = _repository.partialTranscripts.listen(
      (partial) {
        if (!_disposed) {
          state.value = _stopping
              ? VoiceTranscribing(partial)
              : VoiceRecording(partial);
        }
      },
      onError: (_) {
        if (!_disposed) {
          state.value = const VoiceUnavailable(VoiceTranscriptionFailed());
        }
      },
    );
    return const VoiceRecording('');
  }

  Future<void> finishSegmentFromUserAction() async {
    if (_disposed) return;
    if (state.value is VoiceStarting) {
      _releaseRequested = true;
      return;
    }
    if (state.value is! VoiceRecording) return;
    final partial = switch (state.value) {
      VoiceRecording(:final partialTranscript) => partialTranscript,
      VoiceTranscribing(:final partialTranscript) => partialTranscript,
      _ => '',
    };
    _stopping = true;
    state.value = VoiceTranscribing(partial);
    final result = await _repository.stop();
    _stopping = false;
    await _partialSubscription?.cancel();
    _partialSubscription = null;
    if (_disposed || !_modeActive) return;
    state.value = switch (result) {
      Ok(:final value) => VoiceReady(transcript: value),
      Err(:final failure) => () {
        _modeActive = false;
        return VoiceUnavailable(failure);
      }(),
    };
  }

  Future<void> stopModeFromUserAction() => cancel();

  Future<void> cancel() async {
    _modeActive = false;
    _stopping = false;
    await _partialSubscription?.cancel();
    _partialSubscription = null;
    _releaseRequested = false;
    await _repository.release(releaseModel: true);
    if (!_disposed) state.value = const VoiceIdle();
  }

  Future<void> notifyAppInactive() => cancel();

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _modeActive = false;
    _stopping = false;
    await _partialSubscription?.cancel();
    await _repository.release(releaseModel: true);
    state.dispose();
    hasSelectedModel.dispose();
    language.dispose();
  }
}
