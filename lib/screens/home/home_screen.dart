import 'package:flutter/material.dart';

import '../../core/routes/app_navigation.dart';
import '../../data/jobtrail_store.dart';
import '../../widgets/app_button.dart';
import '../../widgets/placeholder_content.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store, required this.navigation});
  final JobTrailStore store;
  final AppNavigation navigation;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => PlaceholderContent(
      screenId: 'S01',
      title: 'Beranda',
      owner: 'Ichsan',
      children: [
        Text('${store.applications.length} lamaran · data demo in-memory'),
        AppButton(label: 'Tambah Lamaran', onPressed: navigation.openAdd),
      ],
    ),
  );
}
