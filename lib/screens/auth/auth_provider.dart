/// Provider boundary for a future auth integration. No credentials are persisted.
/// A completed signIn is rechecked with restoreSession before opening Home.
/// register/sendReset/resendVerification must complete only after a real provider
/// accepts that request. setPassword requires a provider-validated recovery
/// session. Timeouts in the UI do not cancel provider-side operations.
abstract interface class AuthProvider {
  Future<bool> restoreSession();
  Future<void> signIn(String email, String password);
  Future<void> register(String name, String email, String password);
  Future<void> sendReset(String email);
  Future<void> resendVerification(String email);
  Future<void> setPassword(String password);
}

class AuthUnavailable implements Exception {
  const AuthUnavailable();
  @override
  String toString() =>
      'Autentikasi belum terhubung. Tidak ada akun, sesi, atau email yang dibuat.';
}

class UnavailableAuthProvider implements AuthProvider {
  const UnavailableAuthProvider();
  @override
  Future<bool> restoreSession() async => false;
  @override
  Future<void> signIn(String email, String password) async =>
      throw const AuthUnavailable();
  @override
  Future<void> register(String name, String email, String password) async =>
      throw const AuthUnavailable();
  @override
  Future<void> sendReset(String email) async => throw const AuthUnavailable();
  @override
  Future<void> resendVerification(String email) async =>
      throw const AuthUnavailable();
  @override
  Future<void> setPassword(String password) async =>
      throw const AuthUnavailable();
}
