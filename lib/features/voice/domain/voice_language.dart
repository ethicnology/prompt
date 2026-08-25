enum VoiceLanguage {
  french('fr', 'French'),
  english('en', 'English');

  const VoiceLanguage(this.code, this.label);

  final String code;
  final String label;
}
