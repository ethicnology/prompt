import 'dart:io';

import 'package:record/record.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import '../../../core/async/result.dart';
import '../domain/voice_language.dart';
import 'voice_engine.dart';
import 'voice_engine_platform_stub.dart';

VoiceEngine createVoiceEngine() => switch (Platform.operatingSystem) {
  'android' || 'ios' => AndroidIosWhisperEngine(),
  'linux' => const LinuxWhisperEngineStub(),
  _ => const UnsupportedVoiceEngine(),
};

/// Android/iOS-only adapter. It streams PCM directly to Whisper; no recording
/// is ever written to a file, and model paths are supplied by a user selection.
class AndroidIosWhisperEngine implements VoiceEngine {
  // Keep the selected model resident across short dictation turns. Loading it
  // from storage dominated the latency of every subsequent voice action.
  final WhisperController _controller = WhisperController();

  @override
  Future<Result<void, VoiceEngineFailure>> requestMicrophonePermission() async {
    final recorder = AudioRecorder();
    try {
      return await recorder.hasPermission()
          ? const Ok(null)
          : const Err(VoiceEngineFailure.permissionDenied);
    } on UnsupportedError {
      return const Err(VoiceEngineFailure.permissionUnavailable);
    } catch (_) {
      return const Err(VoiceEngineFailure.permissionDenied);
    } finally {
      await recorder.dispose();
    }
  }

  @override
  Future<Result<VoiceCapture, VoiceEngineFailure>> startCapture({
    required String modelPath,
    required VoiceLanguage language,
  }) async {
    final recorder = AudioRecorder();
    try {
      final pcm16Stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      // The live Whisper session stays open for the whole voice mode, but the
      // microphone starts muted until the user holds push-to-talk.
      await recorder.pause();
      final session = await _controller.transcribeLive(
        modelPath: modelPath,
        pcm16Stream: pcm16Stream,
        // An explicit language avoids the identification pass for every live
        // utterance while keeping French and English available in settings.
        lang: language.code,
        keepModelLoaded: true,
      );
      return Ok(_AndroidIosVoiceCapture(recorder, session));
    } catch (_) {
      await recorder.cancel();
      await recorder.dispose();
      return const Err(VoiceEngineFailure.captureFailed);
    }
  }

  @override
  Future<void> releaseModel() async {
    try {
      await _controller.releaseModel();
    } catch (_) {
      // Releasing a parked model is best-effort after native shutdown errors.
    }
  }
}

class LinuxWhisperEngineStub extends UnsupportedVoiceEngine {
  const LinuxWhisperEngineStub();
}

class _AndroidIosVoiceCapture implements VoiceCapture {
  _AndroidIosVoiceCapture(this._recorder, this._session);

  final AudioRecorder _recorder;
  final WhisperLiveSession _session;
  bool _released = false;
  Future<String>? _finalTranscript;

  @override
  Stream<String> get partialTranscripts => _session.partials;

  @override
  Future<Result<void, VoiceEngineFailure>> resumeMicrophone() async {
    try {
      await _recorder.resume();
      return const Ok(null);
    } catch (_) {
      return const Err(VoiceEngineFailure.captureFailed);
    }
  }

  @override
  Future<Result<void, VoiceEngineFailure>> pauseMicrophone() async {
    try {
      await _recorder.pause();
      return const Ok(null);
    } catch (_) {
      return const Err(VoiceEngineFailure.captureFailed);
    }
  }

  @override
  Future<Result<String, VoiceEngineFailure>> stop() async {
    try {
      await _recorder.stop();
      return Ok(
        await (_finalTranscript ??= _session.stop()).timeout(
          const Duration(seconds: 30),
        ),
      );
    } catch (_) {
      return const Err(VoiceEngineFailure.transcriptionFailed);
    }
  }

  @override
  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      await _recorder.cancel();
    } catch (_) {
      // Continue freeing Whisper and recorder resources after recorder errors.
    }
    try {
      await (_finalTranscript ??= _session.stop()).timeout(
        const Duration(seconds: 30),
      );
    } catch (_) {
      // The final transcript is deliberately discarded during cancellation.
    }
    await _recorder.dispose();
  }
}
