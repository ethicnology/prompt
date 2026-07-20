abstract interface class CredentialsStore {
  Future<void> savePassword(String? password);

  Future<String?> readPassword();

  Future<void> clearPassword();
}
