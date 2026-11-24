import 'package:flutter/material.dart';

import '../../data/jobtrail_store.dart';
import '../../screens/application_form/application_form_screen.dart';
import '../../screens/detail/application_detail_screen.dart';

enum AppTab { home, board, schedule, documents, statistics }

/// One selected tab and one root Navigator. IDs, never copied entities, cross routes.
class AppNavigation extends ChangeNotifier {
  AppNavigation(this.store);
  final JobTrailStore store;
  final navigatorKey = GlobalKey<NavigatorState>();
  AppTab _selectedTab = AppTab.home;
  String? _scheduleApplicationId;
  String? _savedBoardApplicationId;
  AppTab get selectedTab => _selectedTab;
  String? get scheduleApplicationId => _scheduleApplicationId;
  String? get savedBoardApplicationId => _savedBoardApplicationId;

  /// The optional ID scopes Schedule or reveals an application saved by Add.
  void showTab(AppTab tab, {String? applicationId}) {
    _selectedTab = tab;
    _scheduleApplicationId = tab == AppTab.schedule ? applicationId : null;
    _savedBoardApplicationId = tab == AppTab.board ? applicationId : null;
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    notifyListeners();
  }

  Future<void> openDetail(String applicationId) async {
    await navigatorKey.currentState!.push<void>(
      MaterialPageRoute(
        settings: RouteSettings(
          name: '/application/detail',
          arguments: applicationId,
        ),
        builder: (_) => ApplicationDetailScreen(
          store: store,
          navigation: this,
          applicationId: applicationId,
        ),
      ),
    );
  }

  Future<void> openAdd() async {
    final savedId = await navigatorKey.currentState!.push<String>(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/application/add'),
        builder: (_) => ApplicationFormScreen(store: store, navigation: this),
      ),
    );
    if (savedId != null && store.applicationById(savedId) != null) {
      showTab(AppTab.board, applicationId: savedId);
    }
  }

  /// Call from Detail. Successful save pops back to that same live ID.
  Future<void> openEdit(String applicationId) async {
    await navigatorKey.currentState!.push<String>(
      MaterialPageRoute(
        settings: RouteSettings(
          name: '/application/edit',
          arguments: applicationId,
        ),
        builder: (_) => ApplicationFormScreen(
          store: store,
          navigation: this,
          applicationId: applicationId,
        ),
      ),
    );
  }

  /// S04 calls after store.addApplication/updateApplication succeeds.
  void finishForm(String savedId) {
    if (store.applicationById(savedId) == null) {
      throw StateError('Lamaran tersimpan tidak ditemukan.');
    }
    navigatorKey.currentState!.pop<String>(savedId);
  }

  void back() => navigatorKey.currentState!.pop();
}
