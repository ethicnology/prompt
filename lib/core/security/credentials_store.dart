abstract interface class CredentialsStore {
  Future<void> savePassword(String profileId, String? password);

  Future<String?> readPassword(String profileId);

  Future<void> clearPassword(String profileId);
}
