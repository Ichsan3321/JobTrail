import 'package:flutter/material.dart';

import '../../core/routes/app_navigation.dart';
import '../../data/jobtrail_store.dart';
import '../../widgets/app_button.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/placeholder_content.dart';

/// Contract placeholder only. S04 owns validation UI, dirty cancel and save UI.
class ApplicationFormScreen extends StatelessWidget {
  const ApplicationFormScreen({
    super.key,
    required this.store,
    required this.navigation,
    this.applicationId,
  });
  final JobTrailStore store;
  final AppNavigation navigation;
  final String? applicationId;
  bool get isEditing => applicationId != null;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(isEditing ? 'Edit Lamaran' : 'Tambah Lamaran')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final app = isEditing ? store.applicationById(applicationId!) : null;
          if (isEditing && app == null) {
            return const EmptyState(
              message: 'Lamaran tidak ditemukan. Silakan kembali.',
            );
          }
          return PlaceholderContent(
            screenId: 'S04',
            title: isEditing ? 'Edit' : 'Tambah',
            owner: 'Rifqi',
            children: [
              if (app != null)
                Text(app.company, key: const ValueKey('form-company')),
              const Text(
                'Form dan penyimpanan melalui UI belum diimplementasikan.',
              ),
              AppButton(label: 'Batal', onPressed: navigation.back),
            ],
          );
        },
      ),
    ),
  );
}
