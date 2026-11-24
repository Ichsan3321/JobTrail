import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_provider.dart';

class AuthSessionController extends ChangeNotifier {
  AuthSessionController(this.provider) {
    _subscription = provider.sessionChanges.listen(
      (state) {
        if (!_leaving) _apply(state);
      },
      onError: (Object error, StackTrace _) {
        if (!_leaving) _apply(AuthSession.error(_issue(error)));
      },
    );
    unawaited(restore());
  }

  final SessionAuthProvider provider;
  late final StreamSubscription<AuthSession> _subscription;
  AuthSession _state = const AuthSession.loading();
  Timer? _expiry;
  int _generation = 0;
  bool _disposed = false;
  bool _leaving = false;

  AuthSession get state => _state;

  AuthIssue _issue(Object error) => switch (error) {
    AuthIssue issue => issue,
    TimeoutException() => AuthIssue.network,
    _ => AuthIssue.unexpected,
  };

  void _apply(AuthSession next) {
    if (_disposed) return;
    final generation = ++_generation;
    _expiry?.cancel();
    final expiresAt = next.expiresAt;
    if (expiresAt != null) {
      final remaining = expiresAt.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        next = const AuthSession.error(AuthIssue.expired);
      } else {
        _expiry = Timer(remaining, () {
          if (generation == _generation) {
            _apply(const AuthSession.error(AuthIssue.expired));
          }
        });
      }
    }
    _state = next;
    notifyListeners();
  }

  Future<void> restore() async {
    if (_leaving || _disposed) return;
    _apply(const AuthSession.loading());
    final generation = _generation;
    try {
      final state = await provider.readSession().timeout(
        const Duration(seconds: 15),
      );
      if (generation == _generation) _apply(state);
    } catch (error) {
      if (generation == _generation) _apply(AuthSession.error(_issue(error)));
    }
  }

  Future<void> signOut() async {
    if (_leaving || _disposed) return;
    _leaving = true;
    _apply(const AuthSession.loading());
    try {
      await provider.signOut();
      _apply(const AuthSession.signedOut());
    } catch (error) {
      _apply(AuthSession.error(_issue(error)));
    } finally {
      _leaving = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _expiry?.cancel();
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
