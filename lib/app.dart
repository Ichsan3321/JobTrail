import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'core/constants/app_tokens.dart';
import 'core/routes/app_navigation.dart';
import 'core/theme/app_theme.dart';
import 'data/jobtrail_store.dart';
import 'widgets/app_shell.dart';
import 'screens/auth/auth_provider.dart';
import 'screens/auth/auth_screen.dart';

class JobTrailApp extends StatefulWidget {
  const JobTrailApp({
    super.key,
    this.store,
    this.showAuthentication = true,
    this.authProvider = const UnavailableAuthProvider(),
  });

  /// Debug-only shell harness. Profile/release always require the auth gate.
  final bool showAuthentication;
  final AuthProvider authProvider;

  /// Caller owns and disposes an injected store. Otherwise the app owns it.
  final JobTrailStore? store;
  @override
  State<JobTrailApp> createState() => _JobTrailAppState();
}

class _JobTrailAppState extends State<JobTrailApp> {
  late final JobTrailStore store = widget.store ?? JobTrailStore.demo();
  late final AppNavigation navigation = AppNavigation(store);
  @override
  void dispose() {
    navigation.dispose();
    if (widget.store == null) store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'JobTrail',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    navigatorKey: navigation.navigatorKey,
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
    home: (!kDebugMode || widget.showAuthentication)
        ? AuthGate(
            provider: widget.authProvider,
            home: AppShell(store: store, navigation: navigation),
          )
        : AppShell(store: store, navigation: navigation),
  );
}
