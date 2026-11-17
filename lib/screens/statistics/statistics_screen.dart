import 'package:flutter/material.dart';

import '../../data/jobtrail_store.dart';
import '../../widgets/placeholder_content.dart';

class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key, required this.store});
  final JobTrailStore store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => PlaceholderContent(
      screenId: 'S07',
      title: 'Statistik',
      owner: 'Ziyaad',
      children: [
        Text(
          'Total: ${store.applications.length}',
          key: const ValueKey('statistics-total'),
        ),
        for (final entry in store.distribution().entries)
          Text('${entry.key.label}: ${entry.value}'),
      ],
    ),
  );
}
