import 'package:flutter/material.dart';

import '../core/constants/app_tokens.dart';
import '../models/recruitment_status.dart';

extension RecruitmentStatusColors on RecruitmentStatus {
  Color get foreground => switch (this) {
    RecruitmentStatus.applied => const Color(0xFF475569),
    RecruitmentStatus.screening ||
    RecruitmentStatus.test => const Color(0xFFB45309),
    RecruitmentStatus.interview => const Color(0xFF0369A1),
    RecruitmentStatus.offering => const Color(0xFF047857),
    RecruitmentStatus.rejected => const Color(0xFFB91C1C),
  };
  Color get background => switch (this) {
    RecruitmentStatus.applied => const Color(0xFFF1F5F9),
    RecruitmentStatus.screening ||
    RecruitmentStatus.test => const Color(0xFFFEF3C7),
    RecruitmentStatus.interview => const Color(0xFFE0F2FE),
    RecruitmentStatus.offering => const Color(0xFFD1FAE5),
    RecruitmentStatus.rejected => const Color(0xFFFEE2E2),
  };
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});
  final RecruitmentStatus status;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: status.background,
      borderRadius: BorderRadius.circular(AppRadius.chip),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        status.label,
        style: AppTypography.label.copyWith(color: status.foreground),
      ),
    ),
  );
}
