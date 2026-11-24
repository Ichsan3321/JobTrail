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

/// Live providers expose identity and recovery state without exposing tokens.
abstract interface class SessionAuthProvider implements AuthProvider {
  Stream<AuthSession> get sessionChanges;
  Future<AuthSession> readSession();
  Future<void> signOut();
  void dispose();
}

enum AuthPhase { loading, signedOut, authenticated, recovery, error }

class AuthSession {
  const AuthSession.loading() : this._(AuthPhase.loading);
  const AuthSession.signedOut() : this._(AuthPhase.signedOut);
  const AuthSession.authenticated(
    String userId,
    DateTime expiresAt, {
    String? displayName,
    String? email,
  }) : this._(
         AuthPhase.authenticated,
         userId: userId,
         expiresAt: expiresAt,
         displayName: displayName,
         email: email,
       );
  const AuthSession.recovery(String userId, DateTime expiresAt)
    : this._(AuthPhase.recovery, userId: userId, expiresAt: expiresAt);
  const AuthSession.error(AuthIssue issue)
    : this._(AuthPhase.error, issue: issue);
  const AuthSession._(
    this.phase, {
    this.userId,
    this.expiresAt,
    this.issue,
    this.displayName,
    this.email,
  });

  final AuthPhase phase;
  final String? userId;
  final DateTime? expiresAt;
  final AuthIssue? issue;
  final String? displayName;
  final String? email;
}

enum AuthIssue implements Exception {
  invalidCredentials('Email atau password tidak sesuai.'),
  emailUnconfirmed('Konfirmasi email sebelum masuk.'),
  invalidLink(
    'Tautan tidak berlaku atau sudah kedaluwarsa. Minta tautan baru.',
  ),
  expired('Sesi berakhir. Silakan masuk kembali.'),
  network('Koneksi bermasalah. Silakan coba lagi.'),
  rateLimit('Terlalu banyak percobaan. Coba lagi nanti.'),
  weakPassword('Password belum memenuhi persyaratan keamanan.'),
  unexpected('Permintaan gagal. Silakan coba lagi.');

  const AuthIssue(this.message);
  final String message;
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
