import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sdk;

import 'auth_callback_url_stub.dart'
    if (dart.library.js_interop) 'auth_callback_url_web.dart';
import 'auth_configuration.dart';
import 'auth_provider.dart';

class SupabaseAuthProvider implements SessionAuthProvider {
  SupabaseAuthProvider._(
    this._configuration,
    this._auth,
    this._storage,
    this._recovery,
  ) {
    _authSubscription = _auth.onAuthStateChange.listen(
      _authChanged,
      onError: (Object error, StackTrace _) {
        if (!_busy) {
          _eventVersion++;
          _emit(AuthSession.error(_issue(error)));
        }
      },
    );
    _startup = _startLinks();
  }

  static Future<SupabaseAuthProvider> initialize(
    AuthConfiguration configuration,
  ) async {
    final project = configuration.project!;
    final storage = sdk.SharedPreferencesLocalStorage(
      persistSessionKey: 'jobtrail.auth.${project.host}',
    );
    final recovery = sdk.SharedPreferencesLocalStorage(
      persistSessionKey: 'jobtrail.recovery.${project.host}',
    );
    await recovery.initialize();
    final supabase = await sdk.Supabase.initialize(
      url: project.origin,
      publishableKey: configuration.publishableKey,
      debug: false,
      authOptions: sdk.FlutterAuthClientOptions(
        authFlowType: sdk.AuthFlowType.pkce,
        detectSessionInUri: false,
        localStorage: storage,
      ),
    );
    return SupabaseAuthProvider._(
      configuration,
      supabase.client.auth,
      storage,
      recovery,
    );
  }

  final AuthConfiguration _configuration;
  final sdk.GoTrueClient _auth;
  final sdk.LocalStorage _storage;
  final sdk.LocalStorage _recovery;
  final _changes = StreamController<AuthSession>.broadcast();
  late final StreamSubscription<sdk.AuthState> _authSubscription;
  StreamSubscription<Uri>? _linkSubscription;
  late final Future<void> _startup;
  Future<void> _queue = Future.value();
  Uri? _lastCallback;
  bool _busy = false;
  bool _starting = true;
  bool _disposed = false;
  int _eventVersion = 0;
  AuthIssue? _startupError;

  @override
  Stream<AuthSession> get sessionChanges => _changes.stream;

  Future<void> _startLinks() async {
    try {
      if (kIsWeb) {
        await _acceptCallback(Uri.base);
      } else {
        final links = AppLinks();
        _linkSubscription = links.uriLinkStream.listen(
          (uri) => unawaited(_acceptCallback(uri)),
          onError: (Object _, StackTrace _) =>
              _emit(const AuthSession.error(AuthIssue.invalidLink)),
        );
        final initial = await links.getInitialLink();
        if (initial != null) await _acceptCallback(initial);
        await _queue;
      }
    } catch (_) {
      _emit(const AuthSession.error(AuthIssue.invalidLink));
    } finally {
      _starting = false;
    }
  }

  void _emit(AuthSession session) {
    if (_disposed) return;
    if (!_changes.hasListener && session.phase == AuthPhase.error) {
      _startupError = session.issue;
    }
    _changes.add(session);
  }

  Future<T> _command<T>(Future<T> Function() action) {
    final operation = _queue.then((_) async {
      if (_disposed) throw AuthIssue.expired;
      _busy = true;
      _eventVersion++;
      try {
        return await action();
      } catch (error) {
        throw _issue(error);
      } finally {
        _busy = false;
      }
    });
    _queue = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  static AuthIssue _issue(Object error) {
    if (error is AuthIssue) return error;
    if (error is TimeoutException || error is sdk.AuthRetryableFetchException) {
      return AuthIssue.network;
    }
    if (error is sdk.AuthPKCEGrantCodeExchangeError) {
      return AuthIssue.invalidLink;
    }
    if (error is sdk.AuthException) {
      if (error.statusCode == '429') return AuthIssue.rateLimit;
      return switch (error.code) {
        'invalid_credentials' => AuthIssue.invalidCredentials,
        'email_not_confirmed' => AuthIssue.emailUnconfirmed,
        'otp_expired' ||
        'flow_state_expired' ||
        'flow_state_not_found' ||
        'bad_code_verifier' => AuthIssue.invalidLink,
        'refresh_token_not_found' ||
        'refresh_token_already_used' ||
        'session_not_found' ||
        'session_expired' ||
        'bad_jwt' => AuthIssue.expired,
        'over_email_send_rate_limit' ||
        'over_request_rate_limit' => AuthIssue.rateLimit,
        'weak_password' => AuthIssue.weakPassword,
        _ => AuthIssue.unexpected,
      };
    }
    return AuthIssue.unexpected;
  }

  static String? _sessionId(sdk.Session session) {
    try {
      final payload = session.accessToken.split('.')[1];
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(payload))),
      );
      final id = (claims as Map<String, dynamic>)['session_id'];
      return id is String && id.isNotEmpty ? id : null;
    } catch (_) {
      return null;
    }
  }

  Future<AuthSession> _readCurrent() async {
    final marker = await _recovery.accessToken();
    final session = _auth.currentSession;
    if (session == null) {
      return marker == null
          ? const AuthSession.signedOut()
          : const AuthSession.error(AuthIssue.invalidLink);
    }
    final expiresAt = session.expiresAt;
    if (expiresAt == null || session.user.id.isEmpty) {
      return const AuthSession.error(AuthIssue.expired);
    }
    final expiry = DateTime.fromMillisecondsSinceEpoch(
      expiresAt * 1000,
      isUtc: true,
    );
    if (!expiry.isAfter(DateTime.now())) {
      return const AuthSession.error(AuthIssue.expired);
    }
    if (marker != null) {
      if (marker != _sessionId(session)) {
        return const AuthSession.error(AuthIssue.invalidLink);
      }
      return AuthSession.recovery(session.user.id, expiry);
    }
    return AuthSession.authenticated(session.user.id, expiry);
  }

  Future<void> _authChanged(sdk.AuthState event) async {
    if (_starting || _busy || _disposed) return;
    final generation = ++_eventVersion;
    try {
      final state = await _readCurrent();
      if (generation != _eventVersion || _busy || _disposed) return;
      if (event.event == sdk.AuthChangeEvent.passwordRecovery &&
          state.phase == AuthPhase.authenticated) {
        // Another browser tab can emit the event while its marker is being saved.
        _emit(const AuthSession.error(AuthIssue.invalidLink));
      } else {
        _emit(state);
      }
    } catch (error) {
      if (generation == _eventVersion) _emit(AuthSession.error(_issue(error)));
    }
  }

  Future<void> _acceptCallback(Uri uri) async {
    try {
      final flow = _configuration.callback(uri, onWeb: kIsWeb);
      if (flow == null || _lastCallback == uri || _disposed) return;
      _lastCallback = uri;
      await _command(() async {
        _emit(const AuthSession.loading());
        clearAuthCallbackUrl();
        // Fence both callbacks before the SDK can persist the exchanged session.
        await _recovery.persistSession('pending');
        try {
          final codes = uri.queryParametersAll['code'];
          if (codes == null ||
              codes.length != 1 ||
              codes.single.isEmpty ||
              uri.queryParameters.containsKey('error')) {
            throw AuthIssue.invalidLink;
          }
          final response = await _auth.exchangeCodeForSession(codes.single);
          final isRecovery =
              response.redirectType ==
              sdk.AuthChangeEvent.passwordRecovery.name;
          if (isRecovery != (flow == AuthCallback.recovery)) {
            throw AuthIssue.invalidLink;
          }
          if (isRecovery) {
            final id = _sessionId(response.session);
            if (id == null) throw AuthIssue.invalidLink;
            await _recovery.persistSession(id);
          } else {
            await _recovery.removePersistedSession();
          }
          _emit(await _readCurrent());
        } catch (error) {
          final issue = _issue(error);
          try {
            await _clearSession();
          } catch (_) {
            // A remaining marker fails closed on restart.
          }
          throw issue == AuthIssue.network || issue == AuthIssue.rateLimit
              ? issue
              : AuthIssue.invalidLink;
        }
      });
    } catch (error) {
      _emit(AuthSession.error(_issue(error)));
    }
  }

  @override
  Future<AuthSession> readSession() async {
    await _startup;
    await _queue;
    final error = _startupError;
    _startupError = null;
    if (error != null) return AuthSession.error(error);
    final session = _auth.currentSession;
    if (session != null && session.isExpired) {
      try {
        await _auth.refreshSession();
      } catch (error) {
        return AuthSession.error(_issue(error));
      }
    }
    return _readCurrent();
  }

  @override
  Future<bool> restoreSession() async =>
      (await readSession()).phase == AuthPhase.authenticated;

  Future<void> _prepareSignIn() async {
    if (await _recovery.hasAccessToken()) throw AuthIssue.invalidLink;
  }

  String _redirect(AuthCallback flow) =>
      _configuration.redirect(flow, onWeb: kIsWeb).toString();

  @override
  Future<void> signIn(String email, String password) => _command(() async {
    await _prepareSignIn();
    await _auth.signInWithPassword(email: email, password: password);
    _emit(await _readCurrent());
  });

  @override
  Future<void> register(String name, String email, String password) =>
      _command(() async {
        await _prepareSignIn();
        await _auth.signUp(
          email: email,
          password: password,
          data: {'display_name': name},
          emailRedirectTo: _redirect(AuthCallback.confirmation),
        );
        _emit(await _readCurrent());
      });

  @override
  Future<void> sendReset(String email) => _command(
    () => _auth.resetPasswordForEmail(
      email,
      redirectTo: _redirect(AuthCallback.recovery),
    ),
  );

  @override
  Future<void> resendVerification(String email) => _command(() async {
    await _auth.resend(
      type: sdk.OtpType.signup,
      email: email,
      emailRedirectTo: _redirect(AuthCallback.confirmation),
    );
  });

  @override
  Future<void> setPassword(String password) => _command(() async {
    if ((await _readCurrent()).phase != AuthPhase.recovery) {
      throw AuthIssue.invalidLink;
    }
    await _auth.updateUser(sdk.UserAttributes(password: password));
    try {
      await _clearSession();
    } finally {
      _emit(await _readCurrent());
    }
  });

  Future<void> _clearSession() async {
    try {
      await _auth.signOut(scope: sdk.SignOutScope.local);
    } finally {
      if (_auth.currentSession == null) {
        await _storage.removePersistedSession();
        await _recovery.removePersistedSession();
      }
    }
  }

  @override
  Future<void> signOut() => _command(_clearSession);

  @override
  void dispose() {
    _disposed = true;
    _eventVersion++;
    unawaited(_authSubscription.cancel());
    unawaited(_linkSubscription?.cancel());
    unawaited(_changes.close());
  }
}
