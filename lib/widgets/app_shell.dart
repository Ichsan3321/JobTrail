import 'package:flutter/material.dart';

import '../core/routes/app_navigation.dart';
import '../data/jobtrail_repository.dart';
import '../data/jobtrail_store.dart';
import '../screens/board/board_screen.dart';
import '../screens/documents/documents_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/schedule/schedule_screen.dart';
import '../screens/statistics/statistics_screen.dart';
import 'bottom_navbar.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.store,
    required this.navigation,
    this.signOut,
    this.displayName,
    this.email,
  });
  final JobTrailStore store;
  final AppNavigation navigation;
  final VoidCallback? signOut;
  final String? displayName;
  final String? email;

  void _showAccount(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AccountSheet(
        store: store,
        displayName: displayName,
        email: email,
        signOut: signOut!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: navigation,
    builder: (context, _) => Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (store.isConnected) _SnapshotError(store: store),
            Expanded(
              child: IndexedStack(
                index: navigation.selectedTab.index,
                children: [
                  HomeScreen(
                    store: store,
                    navigation: navigation,
                    displayName: displayName,
                    onAccountPressed: store.isConnected && signOut != null
                        ? () => _showAccount(context)
                        : null,
                  ),
                  BoardScreen(
                    store: store,
                    navigation: navigation,
                    savedApplicationId: navigation.savedBoardApplicationId,
                  ),
                  ScheduleScreen(store: store, navigation: navigation),
                  DocumentsScreen(
                    store: store,
                    isActiveTab: () =>
                        navigation.selectedTab == AppTab.documents,
                  ),
                  StatisticsScreen(store: store),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavbar(
        selectedTab: navigation.selectedTab,
        onSelected: navigation.showTab,
      ),
    ),
  );
}

String _failureMessage(JobTrailStore store) =>
    store.failure?.issue.message ?? RepositoryIssue.unexpected.message;

class _SnapshotError extends StatelessWidget {
  const _SnapshotError({required this.store});
  final JobTrailStore store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => store.phase != StorePhase.error
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text('Snapshot terakhir. ${_failureMessage(store)}'),
                  ),
                ),
                TextButton(
                  onPressed: store.isRefreshing ? null : store.refresh,
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
  );
}

class _AccountSheet extends StatelessWidget {
  const _AccountSheet({
    required this.store,
    required this.displayName,
    required this.email,
    required this.signOut,
  });
  final JobTrailStore store;
  final String? displayName;
  final String? email;
  final VoidCallback signOut;

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Keluar dari JobTrail?'),
        content: const Text('Masuk kembali untuk membuka data akun Anda.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Ya, keluar'),
          ),
        ],
      ),
    );
    // The protected navigator may have been removed while awaiting confirmation.
    if (confirmed == true && context.mounted) signOut();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final refreshing = store.isRefreshing;
      final failed = store.phase == StorePhase.error;
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  displayName ?? 'Akun JobTrail',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 4),
              Text(email ?? 'Email tidak tersedia'),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  refreshing
                      ? 'Memuat ulang data akun…'
                      : failed
                      ? 'Sinkronisasi gagal. ${_failureMessage(store)}'
                      : 'Terhubung ke JobTrail',
                ),
              ),
              if (refreshing) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(semanticsLabel: 'Memuat data'),
              ],
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.refresh_rounded),
                title: const Text('Muat ulang data'),
                enabled: !refreshing && !store.isMutating,
                onTap: refreshing || store.isMutating ? null : store.refresh,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout_rounded),
                title: const Text('Keluar'),
                onTap: () => _confirmSignOut(context),
              ),
            ],
          ),
        ),
      );
    },
  );
}
