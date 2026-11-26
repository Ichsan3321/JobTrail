import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_tokens.dart';
import 'auth_brand.dart';
import 'auth_provider.dart';
import 'cinematic_splash.dart';

enum AuthPage { login, register, forgot, verify, sent, reset }

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.provider, required this.home});
  final AuthProvider provider;
  final Widget home;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _splash = true, _checking = true, _entered = false;
  int _checkId = 0;
  String? _failure;
  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(covariant AuthGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) _check();
  }

  Future<void> _check() async {
    final checkId = ++_checkId;
    setState(() {
      _checking = true;
      _entered = false;
      _failure = null;
    });
    try {
      final session = await widget.provider.restoreSession().timeout(
        const Duration(seconds: 10),
      );
      if (mounted && checkId == _checkId) {
        setState(() {
          _entered = session;
          _checking = false;
        });
      }
    } catch (_) {
      if (mounted && checkId == _checkId) {
        setState(() {
          _checking = false;
          _failure = 'Pemeriksaan sesi gagal.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (_splash) {
      content = CinematicSplash(
        key: const ValueKey('auth-startup-splash'),
        onComplete: () {
          if (mounted) setState(() => _splash = false);
        },
      );
    } else if (_checking || _failure != null) {
      content = Scaffold(
        key: const ValueKey('auth-session-check'),
        body: Center(
          child: _failure == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Pemeriksaan sesi gagal.'),
                    TextButton(
                      onPressed: _check,
                      child: const Text('Coba lagi'),
                    ),
                  ],
                ),
        ),
      );
    } else {
      content = _entered
          ? widget.home
          : AuthScreen(
              key: ObjectKey(widget.provider),
              provider: widget.provider,
              onEnter: () => setState(() => _entered = true),
            );
    }
    return AnimatedSwitcher(
      // Replace the switcher itself when gating an invalidated session: an old
      // entry otherwise retains its original reverse duration and stays visible.
      key: ValueKey(_splash || (!_checking && _failure == null)),
      // Session invalidation must remove protected content immediately.
      duration:
          (!_splash && (_checking || _failure != null)) ||
              MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final reducedMotion = MediaQuery.disableAnimationsOf(context);
          return IgnorePointer(
            ignoring:
                animation.status == AnimationStatus.reverse ||
                (!reducedMotion &&
                    animation.status != AnimationStatus.completed),
            child: ExcludeSemantics(
              excluding: animation.status == AnimationStatus.reverse,
              child: reducedMotion
                  ? child
                  : FadeTransition(opacity: animation, child: child),
            ),
          );
        },
      ),
      child: content,
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.provider,
    required this.onEnter,
    this.cancelRecovery,
    this.initialIssue,
  });
  final AuthProvider provider;
  final VoidCallback onEnter;
  final VoidCallback? cancelRecovery;
  final AuthIssue? initialIssue;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late AuthPage _page = widget.cancelRecovery == null
      ? AuthPage.login
      : AuthPage.reset;
  GlobalKey<FormState> _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  bool _visible = false, _confirmVisible = false, _submitting = false;
  bool _launchingGoogle = false;
  bool get _busy => _submitting || _launchingGoogle;
  String? _error;
  late AuthIssue? _googleIssue = widget.initialIssue;
  bool _preview = false;
  bool get _live => widget.provider is SessionAuthProvider;
  GoogleOAuthProvider? get _googleProvider {
    final provider = widget.provider;
    return provider is GoogleOAuthProvider && provider.canSignInWithGoogle
        ? provider
        : null;
  }

  Future<T> _request<T>(Future<T> request) =>
      _live ? request : request.timeout(const Duration(seconds: 10));

  void _returnToLogin() {
    final cancel = widget.cancelRecovery;
    if (cancel == null) {
      _go(AuthPage.login);
    } else {
      cancel();
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _go(AuthPage page, {bool preview = false}) {
    FocusScope.of(context).unfocus();
    setState(() {
      _form = GlobalKey<FormState>();
      _page = page;
      _error = null;
      _googleIssue = null;
      _preview = preview;
      _password.clear();
      _confirm.clear();
      _visible = false;
      _confirmVisible = false;
    });
  }

  Future<void> _signInWithGoogle() async {
    final provider = _googleProvider;
    if (_busy || provider == null) return;
    setState(() {
      _launchingGoogle = true;
      _error = null;
      _googleIssue = null;
    });
    FocusScope.of(context).unfocus();
    try {
      await provider.signInWithGoogle();
    } catch (error) {
      if (mounted) {
        setState(() {
          _googleIssue = error is AuthIssue && error != AuthIssue.unexpected
              ? error
              : AuthIssue.googleFailed;
        });
      }
    } finally {
      if (mounted) setState(() => _launchingGoogle = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
      _googleIssue = null;
    });
    FocusScope.of(context).unfocus();
    final page = _page;
    try {
      if (_preview) throw const AuthUnavailable();
      switch (page) {
        case AuthPage.login:
          await _request(
            widget.provider.signIn(_email.text.trim(), _password.text),
          );
          if (!mounted || _live) return;
          final session = await widget.provider.restoreSession().timeout(
            const Duration(seconds: 10),
          );
          if (!session) throw const AuthUnavailable();
          if (mounted) widget.onEnter();
        case AuthPage.register:
          await _request(
            widget.provider.register(
              _name.text.trim(),
              _email.text.trim(),
              _password.text,
            ),
          );
          if (mounted) _go(AuthPage.verify);
        case AuthPage.forgot:
          await _request(widget.provider.sendReset(_email.text.trim()));
          if (mounted) _go(AuthPage.sent);
        case AuthPage.verify:
          if (_preview) throw const AuthUnavailable();
          await _request(
            widget.provider.resendVerification(_email.text.trim()),
          );
        case AuthPage.sent:
          if (_preview) throw const AuthUnavailable();
          await _request(widget.provider.sendReset(_email.text.trim()));
        case AuthPage.reset:
          await _request(widget.provider.setPassword(_password.text));
          if (mounted && !_live) _go(AuthPage.login);
      }
    } catch (error) {
      if (mounted) {
        if (page == AuthPage.login && error == AuthIssue.emailUnconfirmed) {
          _go(AuthPage.verify);
        }
        setState(
          () => _error = switch (error) {
            AuthUnavailable() => error.toString(),
            AuthIssue issue => issue.message,
            _ => 'Permintaan gagal. Silakan coba lagi.',
          },
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Wajib diisi.' : null;
  Widget _field(
    String label,
    TextEditingController controller, {
    bool password = false,
    bool confirmation = false,
    bool email = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Text(
            label,
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          label: '$label, wajib diisi',
          child: TextFormField(
            key: ValueKey(
              'auth-field-${confirmation
                  ? 'confirm'
                  : email
                  ? 'email'
                  : password
                  ? 'password'
                  : 'name'}',
            ),
            controller: controller,
            enabled: !_busy,
            obscureText:
                password && !(confirmation ? _confirmVisible : _visible),
            enableSuggestions: !password,
            enableIMEPersonalizedLearning: !password,
            autocorrect: !password,
            keyboardType: email
                ? TextInputType.emailAddress
                : TextInputType.text,
            textInputAction:
                confirmation ||
                    (password && _page == AuthPage.login) ||
                    (email && _page == AuthPage.forgot)
                ? TextInputAction.done
                : TextInputAction.next,
            onFieldSubmitted: (_) {
              if (confirmation ||
                  (password && _page == AuthPage.login) ||
                  (email && _page == AuthPage.forgot)) {
                _submit();
              }
            },
            autofillHints: [
              if (email) AutofillHints.email,
              if (password)
                _page == AuthPage.login
                    ? AutofillHints.password
                    : AutofillHints.newPassword,
              if (!email && !password) AutofillHints.name,
            ],
            validator: (value) {
              final required = _required(value);
              if (required != null) return required;
              if (email &&
                  !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                      .hasMatch(value!.trim())) {
                return 'Masukkan email yang valid.';
              }
              if (password && value!.length < 8) return 'Minimal 8 karakter.';
              if (confirmation && value != _password.text) {
                return 'Konfirmasi password belum cocok.';
              }
              return null;
            },
            decoration: InputDecoration(
              hintText: email
                  ? 'nama@email.com'
                  : password
                  ? (confirmation ? 'Ulangi password' : 'Minimal 8 karakter')
                  : 'Nama lengkap kamu',
              hintStyle: AppTypography.body.copyWith(color: AppColors.gray),
              contentPadding: const EdgeInsets.all(16),
              suffixIcon: password
                  ? IconButton(
                      tooltip: (confirmation ? _confirmVisible : _visible)
                          ? 'Sembunyikan password'
                          : 'Tampilkan password',
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              if (confirmation) {
                                _confirmVisible = !_confirmVisible;
                              } else {
                                _visible = !_visible;
                              }
                            }),
                      icon: Icon(
                        (confirmation ? _confirmVisible : _visible)
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final googleAvailable = _googleProvider != null;
    final feedback = _error ?? _googleIssue?.message;
    final register = _page == AuthPage.register;
    final recovery =
        _page == AuthPage.forgot ||
        _page == AuthPage.verify ||
        _page == AuthPage.sent;
    final title = switch (_page) {
      AuthPage.login => 'Lanjutkan perjalananmu',
      AuthPage.register => 'Mulai langkah barumu',
      AuthPage.forgot => 'Lupa password?',
      AuthPage.verify => 'Cek email kamu',
      AuthPage.sent =>
        _preview ? 'Pratinjau email reset' : 'Permintaan reset diterima',
      AuthPage.reset => 'Buat password baru',
    };
    final tag = switch (_page) {
      AuthPage.login => 'WELCOME BACK',
      AuthPage.register => 'CREATE ACCOUNT',
      AuthPage.forgot => 'ACCOUNT RECOVERY',
      AuthPage.verify => 'ALMOST THERE',
      AuthPage.sent => 'EMAIL SENT',
      AuthPage.reset => 'SECURE YOUR ACCOUNT',
    };
    final description = switch (_page) {
      AuthPage.login =>
        'Masuk untuk mengelola setiap kesempatan karier di satu tempat.',
      AuthPage.register =>
        'Buat akun dan atur proses pencarian kerja serta magang dengan rapi.',
      AuthPage.forgot => 'Masukkan email terdaftar untuk memulihkan akun.',
      AuthPage.verify => 'Periksa email tujuan untuk verifikasi akun.',
      AuthPage.sent => 'Jika email terdaftar, tautan untuk mengatur ulang password akan dikirimkan.',
      AuthPage.reset =>
        'Gunakan password kuat yang belum pernah kamu gunakan untuk JobTrail.',
    };
    final button = switch (_page) {
      AuthPage.login => 'Masuk ke JobTrail',
      AuthPage.register => 'Buat Akun',
      AuthPage.forgot => 'Kirim Link Reset',
      AuthPage.verify => 'Kirim Ulang Email',
      AuthPage.sent => 'Kirim Ulang Link',
      AuthPage.reset => 'Simpan Password Baru',
    };
    return PopScope(
      canPop: _page == AuthPage.login,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _returnToLogin();
      },
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            key: ValueKey(_page),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(24, 34, 24, 24),
            child: AutofillGroup(
              onDisposeAction: AutofillContextAction.cancel,
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_preview)
                      _notice(
                        'Pratinjau UI pengembangan. Tidak ada email terkirim atau perubahan akun.',
                      ),
                    const AuthBrand(),
                    SizedBox(
                      height: recovery
                          ? 90
                          : register
                          ? 32
                          : 46,
                    ),
                    if (recovery) ...[
                      Center(
                        child: Image.asset(
                          'assets/home/auth-envelope.png',
                          width: 80,
                          height: 80,
                          excludeFromSemantics: true,
                        ),
                      ),
                      const SizedBox(height: 36),
                    ],
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          _preview ? 'PRATINJAU PENGEMBANGAN' : tag,
                          style: AppTypography.label.copyWith(
                            fontSize: 10,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      title,
                      style: AppTypography.heading.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: AppTypography.body.copyWith(
                        color: AppColors.gray,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (register) _field('Nama lengkap', _name),
                    if (_page == AuthPage.login ||
                        register ||
                        _page == AuthPage.forgot)
                      _field('Email', _email, email: true),
                    if (_page == AuthPage.login ||
                        register ||
                        _page == AuthPage.reset)
                      _field(
                        _page == AuthPage.reset ? 'Password baru' : 'Password',
                        _password,
                        password: true,
                      ),
                    if (register || _page == AuthPage.reset)
                      _field(
                        'Konfirmasi password',
                        _confirm,
                        password: true,
                        confirmation: true,
                      ),
                    if (_page == AuthPage.verify)
                      _notice(
                        _email.text.isEmpty ? 'nama@email.com' : _email.text,
                      ),
                    if (_page == AuthPage.login)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy ? null : () => _go(AuthPage.forgot),
                          child: const Text('Lupa password?'),
                        ),
                      ),
                    if (feedback != null)
                      Semantics(
                        liveRegion: true,
                        child: _notice(
                          feedback,
                          error: _googleIssue != AuthIssue.googleCancelled,
                        ),
                      ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 50),
                      ),
                      child: _submitting
                          ? Semantics(
                              label: 'Memproses permintaan',
                              liveRegion: true,
                              child: const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : Text(button),
                    ),
                    if (_page == AuthPage.login || register) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Center(
                          child: Text('atau', style: AppTypography.label),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: googleAvailable && !_busy
                            ? _signInWithGoogle
                            : null,
                        child: _launchingGoogle
                            ? Semantics(
                                liveRegion: true,
                                child: const Text('Membuka Google…'),
                              )
                            : Text(
                                googleAvailable
                                    ? 'Lanjutkan dengan Google'
                                    : 'Google Sign-In belum tersedia',
                              ),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _go(
                                register ? AuthPage.login : AuthPage.register,
                              ),
                        child: Text(
                          register
                              ? 'Sudah punya akun? Masuk'
                              : 'Belum punya akun? Daftar sekarang',
                        ),
                      ),
                    ] else
                      TextButton(
                        onPressed: _busy ? null : _returnToLogin,
                        child: const Text('Kembali ke Login'),
                      ),
                    if (!_live)
                      _notice(
                        'UI autentikasi belum terhubung ke penyedia akun. Tidak ada login, pendaftaran, atau email nyata.',
                      ),
                    if (kDebugMode && !_busy && !_live) ...[
                      if (_page == AuthPage.login)
                        TextButton(
                          key: const ValueKey('auth-demo-entry'),
                          onPressed: widget.onEnter,
                          child: const Text(
                            'Demo pengembangan: buka Home tanpa login',
                          ),
                        ),
                      if (register)
                        TextButton(
                          onPressed: () => _go(AuthPage.verify, preview: true),
                          child: const Text(
                            'Pratinjau pengembangan: verifikasi email',
                          ),
                        ),
                      if (_page == AuthPage.forgot)
                        TextButton(
                          onPressed: () => _go(AuthPage.sent, preview: true),
                          child: const Text(
                            'Pratinjau pengembangan: email reset terkirim',
                          ),
                        ),
                      if (_page == AuthPage.sent)
                        TextButton(
                          onPressed: () => _go(AuthPage.reset, preview: true),
                          child: const Text(
                            'Simulasi buka link reset dari email',
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _notice(String text, {bool error = false}) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFFF1F2) : AppColors.primaryLight,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      text,
      style: AppTypography.body.copyWith(
        fontSize: 13,
        color: error ? const Color(0xFFB91C1C) : AppColors.primaryDark,
      ),
    ),
  );
}
