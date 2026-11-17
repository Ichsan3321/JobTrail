import 'package:flutter/material.dart';

import '../../core/routes/app_navigation.dart';
import '../../data/jobtrail_store.dart';
import '../../widgets/app_button.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/placeholder_content.dart';

class BoardScreen extends StatelessWidget {
  const BoardScreen({super.key, required this.store, required this.navigation});
  final JobTrailStore store;
  final AppNavigation navigation;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => PlaceholderContent(
      screenId: 'S02',
      title: 'Board',
      owner: 'Hanif',
      children: [
        AppButton(label: 'Tambah Lamaran', onPressed: navigation.openAdd),
        if (store.applications.isEmpty)
          const EmptyState(message: 'Belum ada lamaran.'),
        for (final app in store.applications)
          ListTile(
            key: ValueKey('application-${app.id}'),
            title: Text(app.company),
            subtitle: Text('${app.position}\n${app.status.label}'),
            isThreeLine: true,
            onTap: () => navigation.openDetail(app.id),
          ),
      ],
    ),
  );
}
