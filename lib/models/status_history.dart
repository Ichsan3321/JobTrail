import 'recruitment_status.dart';

class StatusHistory {
  const StatusHistory({
    required this.id,
    required this.applicationId,
    required this.status,
    required this.changedAt,
  });
  final String id;
  final String applicationId;
  final RecruitmentStatus status;
  final DateTime changedAt;
}
