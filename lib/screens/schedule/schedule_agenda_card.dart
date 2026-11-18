import 'package:flutter/material.dart';

import '../../core/constants/app_tokens.dart';
import '../../models/agenda.dart';
import '../../models/application.dart';
import 'schedule_format.dart';

/// Temporary S05 card following Figma ScheduleCard `269:3871`.
/// Moves to shared `lib/widgets/schedule_card.dart` after Farhad approves.
///
/// The Agenda model has no title/duration/mode/reminder yet, so: title falls
/// back to [AgendaType.label], duration and reminder rows are hidden, and the
/// location row uses the default video icon. No values are invented.
class ScheduleAgendaCard extends StatelessWidget {
  const ScheduleAgendaCard({
    super.key,
    required this.agenda,
    required this.application,
    required this.onTap,
  });
  final Agenda agenda;
  final Application application;
  final VoidCallback onTap;

  static Color typeForeground(AgendaType type) => switch (type) {
    AgendaType.interview => const Color(0xFF0369A1),
    AgendaType.test => const Color(0xFFC2410C),
  };
  static Color typeBackground(AgendaType type) => switch (type) {
    AgendaType.interview => const Color(0xFFE0F2FE),
    AgendaType.test => const Color(0xFFFFEDD5),
  };

  static TextStyle _style(
    double size, {
    Color color = AppColors.navy,
    FontWeight weight = FontWeight.w400,
  }) => TextStyle(
    fontFamily: AppTypography.bodyFamily,
    fontSize: size,
    color: color,
    fontWeight: weight,
  );

  @override
  Widget build(BuildContext context) {
    final foreground = typeForeground(agenda.type);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    ScheduleFormat.timeWib(agenda.scheduledAt),
                    style: _style(15, weight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 2),
                Text('WIB', style: _style(11, color: AppColors.gray)),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Material(
            color: AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              side: const BorderSide(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('agenda-${agenda.id}'),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: typeBackground(agenda.type),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.chip,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.circle,
                                    size: 6,
                                    color: foreground,
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      agenda.type.label,
                                      overflow: TextOverflow.ellipsis,
                                      style: _style(
                                        11,
                                        color: foreground,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: AppColors.navy,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    // Model has no agenda title yet: fall back to type label.
                    Text(
                      agenda.type.label,
                      style: _style(15, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${application.company} · ${application.position}',
                      style: _style(12, color: AppColors.gray),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.border,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.videocam_outlined,
                            size: 14,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            agenda.locationOrLink,
                            style: _style(12, weight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
