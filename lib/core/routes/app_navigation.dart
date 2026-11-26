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
  bool _disposed = false;
  int _navigationGeneration = 0;
  String? _scheduleApplicationId;
  String? _savedBoardApplicationId;
  AppTab get selectedTab => _selectedTab;
  String? get scheduleApplicationId => _scheduleApplicationId;
  String? get savedBoardApplicationId => _savedBoardApplicationId;

  /// The optional ID scopes Schedule or reveals an application saved by Add.
  void showTab(AppTab tab, {String? applicationId}) {
    _navigationGeneration++;
    _selectedTab = tab;
    _scheduleApplicationId = tab == AppTab.schedule ? applicationId : null;
    _savedBoardApplicationId = tab == AppTab.board ? applicationId : null;
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    notifyListeners();
  }

  Future<void> openDetail(String applicationId) async {
    _navigationGeneration++;
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
    if (!store.allowsLocalWrites || _disposed) return;
    final navigator = navigatorKey.currentState!;
    final generation = ++_navigationGeneration;
    final savedId = await navigator.push<String>(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/application/add'),
        builder: (_) => ApplicationFormScreen(store: store, navigation: this),
      ),
    );
    // Add starts from the shell. Its result may select Board only while the
    // same shell still owns navigation and no newer route sits above it.
    if (!_disposed &&
        generation == _navigationGeneration &&
        identical(navigatorKey.currentState, navigator) &&
        !navigator.canPop() &&
        savedId != null &&
        store.applicationById(savedId) != null) {
      showTab(AppTab.board, applicationId: savedId);
    }
  }

  /// Call from Detail. Successful save pops back to that same live ID.
  Future<void> openEdit(String applicationId) async {
    if (!store.allowsLocalWrites || _disposed) return;
    _navigationGeneration++;
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

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
