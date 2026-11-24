import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'core/constants/app_tokens.dart';
import 'core/constants/app_dates.dart';
import 'core/routes/app_navigation.dart';
import 'core/theme/app_theme.dart';
import 'data/jobtrail_store.dart';
import 'widgets/app_shell.dart';
import 'screens/auth/auth_provider.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/auth/auth_brand.dart';
import 'screens/auth/auth_session_controller.dart';
import 'screens/auth/cinematic_splash.dart';

typedef AccountHomeBuilder = Widget Function(
  BuildContext context,
  String userId,
  JobTrailStore store,
  AppNavigation navigation,
  VoidCallback signOut,
);

class JobTrailApp extends StatefulWidget {
  const JobTrailApp({
    super.key,
    this.store,
    this.showAuthentication = true,
    this.authProvider = const UnavailableAuthProvider(),
    this.disposeSessionProvider = false,
    this.accountHomeBuilder,
    this.configurationError,
  });

  /// Debug-only shell harness. Profile/release always require the auth gate.
  final bool showAuthentication;
  final AuthProvider authProvider;
  final bool disposeSessionProvider;
  final AccountHomeBuilder? accountHomeBuilder;
  final String? configurationError;

  /// Caller owns and disposes an injected store. Otherwise the app owns it.
  final JobTrailStore? store;
  @override
  State<JobTrailApp> createState() => _JobTrailAppState();
}

class _JobTrailAppState extends State<JobTrailApp> {
  late final JobTrailStore store = widget.store ?? JobTrailStore.demo();
  AppNavigation? _demoNavigation;
  @override
  void dispose() {
    _demoNavigation?.dispose();
    if (_demoNavigation != null && widget.store == null) store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.configurationError;
    if (error != null) {
      return _AppFrame(
        home: _AccountMessage(title: 'Konfigurasi JobTrail', message: error),
      );
    }
    final provider = widget.authProvider;
    if (provider is SessionAuthProvider) {
      return _SessionApp(
        key: ObjectKey(provider),
        provider: provider,
        disposeProvider: widget.disposeSessionProvider,
        accountHomeBuilder: widget.accountHomeBuilder,
      );
    }
    final navigation = _demoNavigation ??= AppNavigation(store);
    final home = AppShell(store: store, navigation: navigation);
    return _AppFrame(
      navigatorKey: navigation.navigatorKey,
      home: (!kDebugMode || widget.showAuthentication)
          ? AuthGate(provider: provider, home: home)
          : home,
    );
  }
}

class _AppFrame extends StatelessWidget {
  const _AppFrame({this.navigatorKey, required this.home});

  final GlobalKey<NavigatorState>? navigatorKey;
  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'JobTrail',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    navigatorKey: navigatorKey,
    builder: (context, child) => ColoredBox(
      color: AppColors.background,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: child,
        ),
      ),
    ),
    home: home,
  );
}

class _SessionApp extends StatefulWidget {
  const _SessionApp({
    super.key,
    required this.provider,
    required this.disposeProvider,
    this.accountHomeBuilder,
  });

  final SessionAuthProvider provider;
  final bool disposeProvider;
  final AccountHomeBuilder? accountHomeBuilder;

  @override
  State<_SessionApp> createState() => _SessionAppState();
}

class _SessionAppState extends State<_SessionApp> {
  late final _controller = AuthSessionController(widget.provider);
  bool _splash = true;

  @override
  void dispose() {
    _controller.dispose();
    if (widget.disposeProvider) widget.provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final state = _controller.state;
      if (!_splash && state.phase == AuthPhase.authenticated) {
        return _AccountScope(
          key: ValueKey(state.userId),
          userId: state.userId!,
          signOut: _controller.signOut,
          builder: widget.accountHomeBuilder,
        );
      }
      return _AppFrame(
        home: Builder(
          builder: (context) {
            final content = _splash
                ? CinematicSplash(
                    key: const ValueKey('auth-startup-splash'),
                    onComplete: () {
                      if (mounted) setState(() => _splash = false);
                    },
                  )
                : switch (state.phase) {
                    AuthPhase.loading => const Scaffold(
                      body: Center(
                        child: CircularProgressIndicator(
                          semanticsLabel: 'Memeriksa sesi',
                        ),
                      ),
                    ),
                    AuthPhase.error => _AccountMessage(
                      title: 'Pemeriksaan sesi gagal.',
                      message: state.issue!.message,
                      actions: [
                        FilledButton(
                          onPressed: _controller.restore,
                          child: const Text('Coba lagi'),
                        ),
                        TextButton(
                          onPressed: _controller.signOut,
                          child: const Text('Keluar'),
                        ),
                      ],
                    ),
                    _ => AuthScreen(
                      key: ValueKey((state.phase, state.userId)),
                      provider: widget.provider,
                      onEnter: () {},
                      cancelRecovery: state.phase == AuthPhase.recovery
                          ? _controller.signOut
                          : null,
                    ),
                  };
            return AnimatedSwitcher(
              duration:
                  MediaQuery.disableAnimationsOf(context) ||
                      state.phase == AuthPhase.error
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              child: content,
            );
          },
        ),
      );
    },
  );
}

/// The whole protected Navigator, including popup routes, belongs to one user.
class _AccountScope extends StatefulWidget {
  const _AccountScope({
    super.key,
    required this.userId,
    required this.signOut,
    this.builder,
  });

  final String userId;
  final VoidCallback signOut;
  final AccountHomeBuilder? builder;

  @override
  State<_AccountScope> createState() => _AccountScopeState();
}

class _AccountScopeState extends State<_AccountScope> {
  late final _store = JobTrailStore.empty(
    referenceDate: AppDates.wibDate(DateTime.now()),
    clock: DateTime.now,
  );
  late final _navigation = AppNavigation(_store);

  @override
  void dispose() {
    _navigation.dispose();
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AppFrame(
    navigatorKey: _navigation.navigatorKey,
    home: Builder(
      builder: (context) =>
          widget.builder?.call(
            context,
            widget.userId,
            _store,
            _navigation,
            widget.signOut,
          ) ??
          _AccountMessage(
            title: 'Akun terhubung',
            message: 'Penyimpanan JobTrail sedang disiapkan. Lamaran, jadwal, dan dokumen belum tersedia untuk akun ini.',
            actions: [
              OutlinedButton(
                onPressed: widget.signOut,
                child: const Text('Keluar'),
              ),
            ],
          ),
    ),
  );
}

class _AccountMessage extends StatelessWidget {
  const _AccountMessage({
    required this.title,
    required this.message,
    this.actions = const [],
  });

  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const AuthBrand(),
          const SizedBox(height: 32),
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 24),
          ...actions,
        ],
      ),
    ),
  );
}
