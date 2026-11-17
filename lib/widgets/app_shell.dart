import 'package:flutter/material.dart';

import '../core/routes/app_navigation.dart';
import '../data/jobtrail_store.dart';
import '../screens/board/board_screen.dart';
import '../screens/documents/documents_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/schedule/schedule_screen.dart';
import '../screens/statistics/statistics_screen.dart';
import 'bottom_navbar.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.store, required this.navigation});
  final JobTrailStore store;
  final AppNavigation navigation;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: navigation,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('JobTrail')),
      body: SafeArea(
        child: IndexedStack(
          index: navigation.selectedTab.index,
          children: [
            HomeScreen(store: store, navigation: navigation),
            BoardScreen(store: store, navigation: navigation),
            ScheduleScreen(store: store, navigation: navigation),
            DocumentsScreen(store: store),
            StatisticsScreen(store: store),
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
