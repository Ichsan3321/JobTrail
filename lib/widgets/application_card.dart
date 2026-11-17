import 'package:flutter/material.dart';

import '../core/constants/app_tokens.dart';
import '../models/application.dart';
import 'status_chip.dart';

class ApplicationCard extends StatelessWidget {
  const ApplicationCard({
    super.key,
    required this.application,
    required this.onTap,
  });
  final Application application;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              application.company,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(application.position),
            const SizedBox(height: AppSpacing.xs),
            Text('${application.location} · ${application.workType.label}'),
            const SizedBox(height: AppSpacing.sm),
            StatusChip(status: application.status),
          ],
        ),
      ),
    ),
  );
}
