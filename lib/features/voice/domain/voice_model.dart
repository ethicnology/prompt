import 'voice_language.dart';

final class VoiceModel {
  const VoiceModel({
    required this.language,
    required this.encoderPath,
    required this.decoderPath,
    required this.joinerPath,
    required this.tokensPath,
    required this.modelType,
  });

  final VoiceLanguage language;
  final String encoderPath;
  final String decoderPath;
  final String joinerPath;
  final String tokensPath;
  final String modelType;

  List<String> get paths => [encoderPath, decoderPath, joinerPath, tokensPath];

  @override
  bool operator ==(Object other) =>
      other is VoiceModel &&
      language == other.language &&
      encoderPath == other.encoderPath &&
      decoderPath == other.decoderPath &&
      joinerPath == other.joinerPath &&
      tokensPath == other.tokensPath &&
      modelType == other.modelType;

  @override
  int get hashCode => Object.hash(
    language,
    encoderPath,
    decoderPath,
    joinerPath,
    tokensPath,
    modelType,
  );
}
