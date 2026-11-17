import 'package:flutter/material.dart';

import '../../core/routes/app_navigation.dart';
import '../../data/jobtrail_store.dart';
import '../../widgets/app_button.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/placeholder_content.dart';

class ApplicationDetailScreen extends StatelessWidget {
  const ApplicationDetailScreen({
    super.key,
    required this.store,
    required this.navigation,
    required this.applicationId,
  });
  final JobTrailStore store;
  final AppNavigation navigation;
  final String applicationId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Detail Lamaran')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final application = store.applicationById(applicationId);
          if (application == null) {
            return const EmptyState(
              message: 'Lamaran tidak ditemukan. Silakan kembali.',
            );
          }
          return PlaceholderContent(
            screenId: 'S03',
            title: 'Detail',
            owner: 'Lenno',
            children: [
              Text(application.company, key: const ValueKey('detail-company')),
              Text(application.position),
              Text(application.status.label),
              AppButton(
                label: 'Edit Lamaran',
                onPressed: () => navigation.openEdit(applicationId),
              ),
              AppButton(
                label: 'Agenda Terkait',
                onPressed: () => navigation.showTab(
                  AppTab.schedule,
                  applicationId: applicationId,
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
