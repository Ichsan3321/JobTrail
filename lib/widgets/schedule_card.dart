import 'package:flutter/material.dart';

import '../core/constants/app_dates.dart';
import '../core/constants/app_tokens.dart';
import '../models/agenda.dart';
import '../models/application.dart';

class ScheduleCard extends StatelessWidget {
  const ScheduleCard({
    super.key,
    required this.agenda,
    required this.application,
    required this.onTap,
  });
  final Agenda agenda;
  final Application application;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${agenda.type.label} · ${application.company}'),
            Text(AppDates.formatWib(agenda.scheduledAt)),
            Text(agenda.locationOrLink),
          ],
        ),
      ),
    ),
  );
}
