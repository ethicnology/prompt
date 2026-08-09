import 'dart:io';

import 'package:record/record.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import '../../../core/async/result.dart';
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
  Future<Result<VoiceCapture, VoiceEngineFailure>> startCapture(
    String modelPath,
  ) async {
    final recorder = AudioRecorder();
    try {
      final pcm16Stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      final session = await _controller.transcribeLive(
        modelPath: modelPath,
        pcm16Stream: pcm16Stream,
        // French is the application's local dictation default. It avoids the
        // language-identification pass for each live utterance.
        lang: 'fr',
        keepModelLoaded: true,
      );
      return Ok(_AndroidIosVoiceCapture(recorder, session));
    } catch (_) {
      await recorder.cancel();
      await recorder.dispose();
      return const Err(VoiceEngineFailure.captureFailed);
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

  @override
  Stream<String> get partialTranscripts => _session.partials;

  @override
  Future<Result<String, VoiceEngineFailure>> stop() async {
    try {
      await _recorder.stop();
      return Ok(await _session.stop());
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
      await _session.stop();
    } catch (_) {
      // The final transcript is deliberately discarded during cancellation.
    }
    await _recorder.dispose();
  }
}
