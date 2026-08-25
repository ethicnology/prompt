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
  VoiceViewModel(this._repository) {
    unawaited(_restoreInstalledModels());
  }

  final VoiceRepository _repository;
  final ValueNotifier<VoiceUiState> state = ValueNotifier(const VoiceIdle());

  /// Installed models remain available across application restarts.
  final ValueNotifier<bool> hasSelectedModel = ValueNotifier(false);
  final ValueNotifier<Set<VoiceLanguage>> selectedModelLanguages =
      ValueNotifier({});
  final ValueNotifier<Map<VoiceLanguage, double>> modelInstallProgress =
      ValueNotifier({});
  final ValueNotifier<Map<VoiceLanguage, VoiceModelInstallFailure>>
  modelInstallFailures = ValueNotifier({});
  final ValueNotifier<VoiceLanguage> language = ValueNotifier(
    VoiceLanguage.french,
  );
  StreamSubscription<String>? _partialSubscription;
  Timer? _segmentLimitTimer;
  bool _disposed = false;
  bool _releaseRequested = false;
  bool _modeActive = false;
  String _latestTranscript = '';
  String _committedTranscript = '';

  Future<void> _restoreInstalledModels() async {
    final restored = await _repository.restoreInstalledModels();
    if (_disposed) return;
    selectedModelLanguages.value = restored;
    hasSelectedModel.value = _repository.hasSelectedModel(language.value);
  }

  Future<void> installModelFromUserAction(VoiceLanguage modelLanguage) async {
    if (_disposed || modelInstallProgress.value.containsKey(modelLanguage)) {
      return;
    }
    modelInstallFailures.value = {...modelInstallFailures.value}
      ..remove(modelLanguage);
    modelInstallProgress.value = {
      ...modelInstallProgress.value,
      modelLanguage: 0,
    };
    final installed = await _repository.installModelFromUserAction(
      modelLanguage,
      onProgress: (progress) {
        if (_disposed) return;
        modelInstallProgress.value = {
          ...modelInstallProgress.value,
          modelLanguage: progress.clamp(0.0, 1.0).toDouble(),
        };
      },
    );
    if (_disposed) return;
    modelInstallProgress.value = {
      for (final entry in modelInstallProgress.value.entries)
        if (entry.key != modelLanguage) entry.key: entry.value,
    };
    if (installed case Ok()) {
      selectedModelLanguages.value = {
        ...selectedModelLanguages.value,
        modelLanguage,
      };
    } else if (installed case Err(:final failure)) {
      modelInstallFailures.value = {
        ...modelInstallFailures.value,
        modelLanguage: failure as VoiceModelInstallFailure,
      };
    }
    hasSelectedModel.value = _repository.hasSelectedModel(language.value);
  }

  Future<void> removeModelFromUserAction(VoiceLanguage modelLanguage) async {
    if (_disposed || modelInstallProgress.value.containsKey(modelLanguage)) {
      return;
    }
    await _repository.removeModel(modelLanguage);
    if (_disposed) return;
    selectedModelLanguages.value = {
      for (final language in selectedModelLanguages.value)
        if (language != modelLanguage) language,
    };
    modelInstallFailures.value = {...modelInstallFailures.value}
      ..remove(modelLanguage);
    hasSelectedModel.value = _repository.hasSelectedModel(language.value);
  }

  /// Called only from the visible voice control's user gesture.
  Future<void> selectModelFromUserAction(VoiceLanguage modelLanguage) async {
    if (_disposed) return;
    final selected = await _repository.selectModelFromUserAction(modelLanguage);
    if (selected) {
      selectedModelLanguages.value = {
        ...selectedModelLanguages.value,
        modelLanguage,
      };
    }
    hasSelectedModel.value = _repository.hasSelectedModel(language.value);
  }

  void selectLanguage(VoiceLanguage value) {
    if (_disposed || _modeActive) return;
    language.value = value;
    hasSelectedModel.value = _repository.hasSelectedModel(value);
  }

  Future<void> enterModeFromUserAction() async {
    if (_disposed) return;
    _modeActive = true;
    _latestTranscript = '';
    _committedTranscript = '';
    state.value = const VoiceStarting();
    final result = await _repository.prepareFromUserAction(language.value);
    if (_disposed || !_modeActive) {
      await _repository.release(releaseModel: true);
      return;
    }
    switch (result) {
      case Ok():
        state.value = const VoiceReady();
      case Err(:final failure):
        _modeActive = false;
        state.value = VoiceUnavailable(failure);
    }
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
        _latestTranscript = '';
        _listenForPartials();
        state.value = VoiceRecording(_committedTranscript);
        _segmentLimitTimer = Timer(
          const Duration(seconds: 30),
          finishSegmentFromUserAction,
        );
        if (_releaseRequested) {
          await finishSegmentFromUserAction();
        }
      case Err(:final failure):
        _modeActive = false;
        state.value = VoiceUnavailable(failure);
    }
  }

  void _listenForPartials() {
    _partialSubscription?.cancel();
    _partialSubscription = _repository.partialTranscripts.listen(
      (partial) {
        if (!_disposed) {
          _latestTranscript = partial;
          final transcript = _joinTranscript(_committedTranscript, partial);
          state.value = switch (state.value) {
            VoiceRecording() => VoiceRecording(transcript),
            VoiceTranscribing() => VoiceTranscribing(transcript),
            _ => VoiceReady(transcript: transcript),
          };
        }
      },
      onError: (_) {
        if (!_disposed) {
          state.value = const VoiceUnavailable(VoiceTranscriptionFailed());
        }
      },
    );
  }

  Future<void> finishSegmentFromUserAction() async {
    if (_disposed) return;
    if (state.value is VoiceStarting) {
      _releaseRequested = true;
      return;
    }
    if (state.value is! VoiceRecording) return;
    _segmentLimitTimer?.cancel();
    _segmentLimitTimer = null;
    state.value = VoiceTranscribing(
      _joinTranscript(_committedTranscript, _latestTranscript),
    );
    final result = await _repository.stop();
    await _partialSubscription?.cancel();
    _partialSubscription = null;
    if (_disposed || !_modeActive) return;
    state.value = switch (result) {
      Ok(:final value) => () {
        _committedTranscript = _joinTranscript(
          _committedTranscript,
          _normalizeTranscript(value),
        );
        _latestTranscript = '';
        return VoiceReady(transcript: _committedTranscript);
      }(),
      Err(:final failure) => () {
        _modeActive = false;
        return VoiceUnavailable(failure);
      }(),
    };
  }

  Future<void> stopModeFromUserAction() async {
    if (_disposed || !_modeActive) return;
    if (state.value is VoiceRecording) {
      await finishSegmentFromUserAction();
      if (_disposed || state.value is VoiceUnavailable) return;
    }
    state.value = VoiceTranscribing(_committedTranscript);
    final corrected = await _repository.finalizeMode();
    if (_disposed || !_modeActive) return;
    switch (corrected) {
      case Ok(:final value) when value.trim().isNotEmpty:
        _committedTranscript = _normalizeTranscript(value);
      case Err(:final failure):
        await _repository.release(releaseModel: true);
        _modeActive = false;
        state.value = VoiceUnavailable(failure);
        return;
      case Ok():
        break;
    }
    // Publish the corrected draft before VoiceIdle ends the mode. ValueNotifier
    // listeners run synchronously, so the composer receives the replacement.
    state.value = VoiceReady(transcript: _committedTranscript);
    _segmentLimitTimer?.cancel();
    _segmentLimitTimer = null;
    await _repository.release(releaseModel: true);
    _modeActive = false;
    state.value = const VoiceIdle();
  }

  Future<void> cancel() async {
    _modeActive = false;
    _segmentLimitTimer?.cancel();
    _segmentLimitTimer = null;
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
    _segmentLimitTimer?.cancel();
    await _partialSubscription?.cancel();
    await _repository.release(releaseModel: true);
    state.dispose();
    hasSelectedModel.dispose();
    selectedModelLanguages.dispose();
    modelInstallProgress.dispose();
    modelInstallFailures.dispose();
    language.dispose();
  }

  String _joinTranscript(String before, String after) {
    final left = before.trim();
    final right = _normalizeTranscript(after);
    if (left.isEmpty) return right;
    if (right.isEmpty) return left;
    return '$left $right';
  }

  String _normalizeTranscript(String value) => value.trim().toLowerCase();
}
