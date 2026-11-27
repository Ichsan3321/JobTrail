import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sdk;

import '../../data/jobtrail_repository.dart';
import '../../data/supabase_jobtrail_repository.dart';
import 'auth_callback_url_stub.dart'
    if (dart.library.js_interop) 'auth_callback_url_web.dart';
import 'auth_configuration.dart';
import 'auth_provider.dart';

class SupabaseAuthProvider implements GoogleOAuthProvider {
  SupabaseAuthProvider._(
    this._configuration,
    this._client,
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
      supabase.client,
      storage,
      recovery,
    );
  }

  final AuthConfiguration _configuration;
  final sdk.SupabaseClient _client;
  sdk.GoTrueClient get _auth => _client.auth;

  JobTrailRepository repositoryFor(String userId) {
    final boundSession = _auth.currentSession;
    final sessionId = _sessionId(boundSession);
    final abort = Completer<void>();
    sdk.Session? activeSession() {
      final current = _auth.currentSession;
      if (_disposed ||
          _busy ||
          current == null ||
          current.isExpired ||
          current.user.id != userId ||
          sessionId == null ||
          _sessionId(current) != sessionId) {
        return null;
      }
      return current;
    }

    return SupabaseJobTrailRepository(
      (name, params) async {
        final session = activeSession();
        if (session == null) {
          throw const RepositoryFailure(RepositoryIssue.authentication);
        }
        // The SDK may consult a newer global session when sending. An explicit
        // request header pins the credential captured for this owner and session.
        try {
          return await _client
              .rpc<Object?>(name, params: params)
              .setHeader('Authorization', 'Bearer ${session.accessToken}')
              .retry(
                enabled: false,
                requestTimeout: const Duration(seconds: 15),
              )
              .abortSignal(abort.future);
        } on sdk.PostgrestException catch (error) {
          if (!abort.isCompleted &&
              activeSession()?.accessToken == session.accessToken &&
              const {'PGRST301', 'PGRST303', '401'}.contains(error.code)) {
            _emit(const AuthSession.error(AuthIssue.expired));
          }
          rethrow;
        }
      },
      isActive: () => activeSession() != null,
      onDispose: abort.complete,
    );
  }

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
  AuthSession? _startupFeedback;
  Future<void>? _googleLaunch;

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
    if (!_changes.hasListener && session.issue != null) {
      _startupFeedback = session;
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

  static String? _sessionId(sdk.Session? session) {
    if (session == null) return null;
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
    final user = session.user;
    final metadata = user.userMetadata;
    String? displayName;
    for (final key in ['display_name', 'full_name', 'name']) {
      final value = metadata?[key];
      if (value is String && value.trim().isNotEmpty) {
        displayName = value.trim();
        break;
      }
    }
    return AuthSession.authenticated(
      user.id,
      expiry,
      displayName: displayName,
      email: user.email,
    );
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
        clearAuthCallbackUrl();
        final isGoogle = flow == AuthCallback.google;
        // Google is launched from Login. A return in a signed-in tab should
        // leave that tab's restored session alone.
        if (isGoogle && _auth.currentSession != null) return;
        _emit(const AuthSession.loading());
        final codes = uri.queryParametersAll['code'];
        final hasCode =
            codes != null && codes.length == 1 && codes.single.isNotEmpty;
        if (isGoogle) {
          final issue = _googleRedirectIssue(uri);
          if (issue != null || !hasCode) {
            await _reportGoogleCallbackIssue(issue ?? AuthIssue.googleFailed);
            return;
          }
        }
        // Fence callbacks before the SDK can persist the exchanged session.
        await _recovery.persistSession('pending');
        try {
          if (!hasCode || uri.queryParameters.containsKey('error')) {
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
          if (isGoogle) {
            await _reportGoogleCallbackIssue(
              issue == AuthIssue.network || issue == AuthIssue.rateLimit
                  ? issue
                  : AuthIssue.googleFailed,
            );
            return;
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

  AuthIssue? _googleRedirectIssue(Uri uri) {
    // Supabase can return the same error in the query and the fragment.
    final fragment = Uri.splitQueryString(uri.fragment);
    final query = uri.queryParameters;
    final error = query['error'] ?? fragment['error'];
    final code = query['error_code'] ?? fragment['error_code'];
    if (error == null && code == null) return null;
    return error == 'access_denied' && (code == null || code.isEmpty)
        ? AuthIssue.googleCancelled
        : AuthIssue.googleFailed;
  }

  Future<void> _reportGoogleCallbackIssue(AuthIssue issue) async {
    final current = await _readCurrent();
    _emit(
      current.phase == AuthPhase.signedOut
          ? AuthSession.signedOut(issue: issue)
          : current,
    );
  }

  @override
  Future<AuthSession> readSession() async {
    await _startup;
    await _queue;
    final feedback = _startupFeedback;
    _startupFeedback = null;
    if (feedback != null) return feedback;
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
  bool get canSignInWithGoogle =>
      _configuration.allowsGoogleOAuth(Uri.base, onWeb: kIsWeb);

  @override
  Future<void> signInWithGoogle() => _googleLaunch ??= _command(() async {
    if (!canSignInWithGoogle || _auth.currentSession != null) {
      throw AuthIssue.googleFailed;
    }
    await _prepareSignIn();
    final launched = await _auth.signInWithOAuth(
      sdk.OAuthProvider.google,
      redirectTo: _redirect(AuthCallback.google),
      scopes: 'openid', // Supabase's Google provider adds email and profile.
      queryParams: const {'prompt': 'select_account'},
    );
    if (!launched) throw AuthIssue.googleFailed;
  }).whenComplete(() => _googleLaunch = null);

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
