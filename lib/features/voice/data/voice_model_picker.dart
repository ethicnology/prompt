import 'package:file_picker/file_picker.dart';

import '../domain/voice_language.dart';
import '../domain/voice_model.dart';

/// Selects user-owned Sherpa model files only after an explicit UI action.
abstract interface class VoiceModelPicker {
  Future<VoiceModel?> pickModelFromUserAction(VoiceLanguage language);
}

class FilePickerVoiceModelPicker implements VoiceModelPicker {
  const FilePickerVoiceModelPicker();

  @override
  Future<VoiceModel?> pickModelFromUserAction(VoiceLanguage language) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select encoder, decoder, joiner, and tokens.txt',
      type: FileType.any,
      allowMultiple: true,
    );
    if (result == null) return null;

    String? match(String fragment, {bool preferInt8 = false}) {
      final matches = result.files
          .where(
            (file) =>
                file.path != null && file.name.toLowerCase().contains(fragment),
          )
          .toList(growable: false);
      if (matches.isEmpty) return null;
      if (preferInt8) {
        for (final file in matches) {
          if (file.name.toLowerCase().contains('int8')) return file.path;
        }
      }
      for (final file in matches) {
        if (!file.name.toLowerCase().contains('int8')) return file.path;
      }
      return matches.first.path;
    }

    final encoder = match('encoder', preferInt8: true);
    final decoder = match('decoder');
    final joiner = match('joiner', preferInt8: true);
    final tokens = result.files
        .where((file) => file.name.toLowerCase() == 'tokens.txt')
        .firstOrNull
        ?.path;
    if (encoder == null ||
        decoder == null ||
        joiner == null ||
        tokens == null) {
      return null;
    }
    return VoiceModel(
      language: language,
      encoderPath: encoder,
      decoderPath: decoder,
      joinerPath: joiner,
      tokensPath: tokens,
      modelType: switch (language) {
        VoiceLanguage.french => 'zipformer',
        VoiceLanguage.english => 'zipformer2',
      },
    );
  }
}
