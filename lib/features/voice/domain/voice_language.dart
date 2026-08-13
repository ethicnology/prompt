enum VoiceLanguage {
  frenchAndEnglish('auto', 'French + English');

  const VoiceLanguage(this.code, this.label);

  final String code;
  final String label;
}
