import 'package:flutter/material.dart';

import '../../core/constants/app_dates.dart';
import '../../core/routes/app_navigation.dart';
import '../../data/jobtrail_store.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/placeholder_content.dart';

class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({
    super.key,
    required this.store,
    required this.navigation,
  });
  final JobTrailStore store;
  final AppNavigation navigation;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final filter = navigation.scheduleApplicationId;
      final agendas = filter == null ? store.agendas : store.agendasFor(filter);
      return PlaceholderContent(
        screenId: 'S05',
        title: 'Jadwal',
        owner: 'Fachriza',
        children: [
          if (filter != null)
            TextButton(
              onPressed: () => navigation.showTab(AppTab.schedule),
              child: const Text('Tampilkan semua agenda'),
            ),
          if (agendas.isEmpty) const EmptyState(message: 'Belum ada agenda.'),
          for (final agenda in agendas)
            ListTile(
              key: ValueKey('agenda-${agenda.id}'),
              title: Text(store.applicationById(agenda.applicationId)!.company),
              subtitle: Text(
                '${agenda.type.label}\n${AppDates.formatWib(agenda.scheduledAt)}',
              ),
              isThreeLine: true,
              onTap: () => navigation.openDetail(agenda.applicationId),
            ),
        ],
      );
    },
  );
}
